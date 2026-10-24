"""CacaoGrade AI - train MobileNetV3-Small -> model/cacao_model.onnx
Contract: input (1,224,224,3) float32 0..1 -> 4 scores in CLASS_LABELS order."""
from __future__ import annotations
import argparse, time
from pathlib import Path
import numpy as np, torch, torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, models, transforms

CLASS_LABELS = ["unfermented", "partially_fermented", "well_fermented", "over_fermented"]
SIZE, MEAN, STD = 224, (0.485, 0.456, 0.406), (0.229, 0.224, 0.225)
HERE = Path(__file__).resolve().parent


class Net(nn.Module):
    def __init__(self, pretrained=True):
        super().__init__()
        w = models.MobileNet_V3_Small_Weights.DEFAULT if pretrained else None
        self.features = models.mobilenet_v3_small(weights=w).features
        self.pool, self.head = nn.AdaptiveAvgPool2d(1), nn.Sequential(nn.Dropout(0.3), nn.Linear(576, 4))
        self.register_buffer("mean", torch.tensor(MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(STD).view(1, 3, 1, 1))

    def forward(self, x):                      # NCHW 0..1
        return self.head(self.pool(self.features((x - self.mean) / self.std)).flatten(1))


class ExportWrapper(nn.Module):
    """Exactly what classifier.py sends: (N,H,W,3) -> (N,4)."""
    def __init__(self, net): super().__init__(); self.net = net
    def forward(self, x): return self.net(x.permute(0, 3, 1, 2).contiguous())


def load_split(root, name, augment):
    tf = (transforms.Compose([transforms.Resize((SIZE, SIZE)), transforms.RandomHorizontalFlip(),
                              transforms.RandomRotation(15), transforms.ColorJitter(.2, .2),
                              transforms.ToTensor()]) if augment else
          transforms.Compose([transforms.Resize((SIZE, SIZE)), transforms.ToTensor()]))
    ds = datasets.ImageFolder(root / name, transform=tf)
    if set(ds.classes) != set(CLASS_LABELS):
        raise SystemExit(f"{name}: expected {CLASS_LABELS}, got {ds.classes}")
    old = list(ds.classes)
    ds.samples = [(p, CLASS_LABELS.index(old[i])) for p, i in ds.samples]   # service order!
    ds.imgs, ds.targets = ds.samples, [t for _, t in ds.samples]
    ds.classes, ds.class_to_idx = list(CLASS_LABELS), {c: i for i, c in enumerate(CLASS_LABELS)}
    return ds


def acc(net, dl, device):
    net.eval(); c = t = 0
    with torch.no_grad():
        for xb, yb in dl:
            pred = net(xb.to(device)).argmax(1).cpu()
            c += int((pred == yb).sum()); t += yb.numel()
    return c / max(t, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=str(HERE / "dataset"))
    ap.add_argument("--epochs", type=int, default=10)
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--no-pretrained", action="store_true")
    ap.add_argument("--out", default=str(HERE / "model" / "cacao_model.onnx"))
    args = ap.parse_args()

    root = Path(args.data)
    if not (root / "train").is_dir():
        raise SystemExit(f"missing {root}\\train - run prepare_data.py first")
    tr, va, te = (load_split(root, n, n == "train") for n in ("train", "valid", "test"))
    tl, vl, sl = (DataLoader(d, batch_size=args.batch, shuffle=(d is tr), num_workers=0)
                  for d in (tr, va, te))

    counts = torch.bincount(torch.tensor(tr.targets), minlength=4).float()
    weights = counts.sum() / (4 * counts.clamp(min=1))      # counter the 13:1 imbalance
    crit = nn.CrossEntropyLoss(weight=weights)
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    net = Net(not args.no_pretrained).to(dev)
    opt = torch.optim.AdamW(net.parameters(), lr=args.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=args.epochs)

    print(f"device={dev}  train/valid/test = {len(tr)}/{len(va)}/{len(te)}")
    print("counts:", dict(zip(CLASS_LABELS, counts.int().tolist())),
          " weights:", [round(w, 2) for w in weights.tolist()])

    best, best_acc, t0 = None, 0.0, time.time()
    for e in range(1, args.epochs + 1):
        net.train(); run = 0.0
        for xb, yb in tl:
            opt.zero_grad(); loss = crit(net(xb.to(dev)), yb.to(dev)); loss.backward(); opt.step()
            run += float(loss) * yb.numel()
        sched.step()
        va_acc = acc(net, vl, dev)
        if va_acc >= best_acc:
            best_acc, best = va_acc, {k: v.clone() for k, v in net.state_dict().items()}
        print(f"epoch {e:>2}/{args.epochs}  loss={run/len(tr):.4f}  valid={va_acc:.3f}  "
              f"({time.time()-t0:.0f}s)")

    net.load_state_dict(best)
    print(f"BEST valid={best_acc:.3f}  test={acc(net, sl, dev):.3f}  total={time.time()-t0:.0f}s")

    out = Path(args.out); out.parent.mkdir(parents=True, exist_ok=True)
    wrap, dummy = ExportWrapper(net).eval(), torch.zeros(1, SIZE, SIZE, 3)
    errs = []
    for kw in (dict(opset_version=17, input_names=["image"], output_names=["scores"], dynamo=False),
               dict(opset_version=17, input_names=["image"], output_names=["scores"]),
               dict(input_names=["image"], output_names=["scores"], dynamo=True)):
        try:
            torch.onnx.export(wrap, (dummy,), str(out), **kw); break
        except Exception as exc:
            errs.append(f"{type(exc).__name__}: {exc}")
    else:
        raise SystemExit("ONNX export failed:\n" + "\n".join(errs) +
                         "\nHint: pip install onnx  (o pip install onnxscript)")

    try:
        import onnxruntime as ort
        sess = ort.InferenceSession(str(out), providers=["CPUExecutionProvider"])
        y = sess.run(None, {sess.get_inputs()[0].name: np.random.rand(1, SIZE, SIZE, 3).astype("float32")})[0]
        print("verified:", sess.get_inputs()[0].shape, "->", y.shape, " logits ok")
    except ImportError:
        print("onnxruntime walay - kini man ang gamit sa service, i-install: pip install onnxruntime")
    print(f"\nWROTE {out}\nNext: i-restart ang RUN_CNN.bat, then GET /health -> engine should be 'cnn'")


if __name__ == "__main__":
    main()