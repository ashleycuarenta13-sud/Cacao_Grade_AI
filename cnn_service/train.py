
"""CacaoGrade AI - Train MobileNetV3-Small and export an ONNX model.

Input:  (1, 224, 224, 3), float32, values from 0 to 1.
Output: Four scores ordered according to CLASS_LABELS.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, models, transforms


CLASS_LABELS = [
    "unfermented",
    "partially_fermented",
    "well_fermented",
    "over_fermented",
]

SIZE = 224
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)
HERE = Path(__file__).resolve().parent


class Net(nn.Module):
    def __init__(self, pretrained=True):
        super().__init__()

        weights = (
            models.MobileNet_V3_Small_Weights.DEFAULT
            if pretrained
            else None
        )

        self.features = models.mobilenet_v3_small(
            weights=weights
        ).features

        self.pool = nn.AdaptiveAvgPool2d(1)
        self.head = nn.Sequential(
            nn.Dropout(0.3),
            nn.Linear(576, 4),
        )

        self.register_buffer(
            "mean",
            torch.tensor(MEAN).view(1, 3, 1, 1),
        )
        self.register_buffer(
            "std",
            torch.tensor(STD).view(1, 3, 1, 1),
        )

    def forward(self, x):
        """Process an NCHW image tensor with values from 0 to 1."""
        x = (x - self.mean) / self.std
        x = self.features(x)
        x = self.pool(x).flatten(1)
        return self.head(x)


class ExportWrapper(nn.Module):
    """Convert NHWC input images into NCHW tensors for the model."""

    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, x):
        return self.net(x.permute(0, 3, 1, 2).contiguous())


def load_split(root, name, augment):
    if augment:
        transform = transforms.Compose([
            transforms.Resize((SIZE, SIZE)),
            transforms.RandomHorizontalFlip(),
            transforms.RandomRotation(15),
            transforms.ColorJitter(0.2, 0.2),
            transforms.ToTensor(),
        ])
    else:
        transform = transforms.Compose([
            transforms.Resize((SIZE, SIZE)),
            transforms.ToTensor(),
        ])

    dataset = datasets.ImageFolder(
        root / name,
        transform=transform,
    )

    if set(dataset.classes) != set(CLASS_LABELS):
        raise SystemExit(
            f"{name}: Expected classes {CLASS_LABELS}, "
            f"but found {dataset.classes}"
        )

    original_classes = list(dataset.classes)

    dataset.samples = [
        (path, CLASS_LABELS.index(original_classes[index]))
        for path, index in dataset.samples
    ]

    dataset.imgs = dataset.samples
    dataset.targets = [target for _, target in dataset.samples]
    dataset.classes = list(CLASS_LABELS)
    dataset.class_to_idx = {
        label: index
        for index, label in enumerate(CLASS_LABELS)
    }

    return dataset


def accuracy(net, data_loader, device):
    net.eval()
    correct = 0
    total = 0

    with torch.no_grad():
        for images, labels in data_loader:
            predictions = net(images.to(device)).argmax(1).cpu()

            correct += int((predictions == labels).sum())
            total += labels.numel()

    return correct / max(total, 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default=str(HERE / "dataset"))
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--no-pretrained", action="store_true")
    parser.add_argument(
        "--out",
        default=str(HERE / "model" / "cacao_model.onnx"),
    )

    args = parser.parse_args()
    root = Path(args.data)

    for split in ("train", "valid", "test"):
        if not (root / split).is_dir():
            raise SystemExit(f"Missing dataset folder: {root / split}")

    train_data, valid_data, test_data = (
        load_split(root, split, split == "train")
        for split in ("train", "valid", "test")
    )

    train_loader, valid_loader, test_loader = (
        DataLoader(
            dataset,
            batch_size=args.batch,
            shuffle=(dataset is train_data),
            num_workers=0,
        )
        for dataset in (train_data, valid_data, test_data)
    )

    class_counts = torch.bincount(
        torch.tensor(train_data.targets),
        minlength=4,
    ).float()

    # Apply class weights to reduce the effect of class imbalance.
    class_weights = (
        class_counts.sum()
        / (4 * class_counts.clamp(min=1))
    )

    criterion = nn.CrossEntropyLoss(weight=class_weights)

    device = torch.device(
        "cuda" if torch.cuda.is_available() else "cpu"
    )

    net = Net(not args.no_pretrained).to(device)
    optimizer = torch.optim.AdamW(
        net.parameters(),
        lr=args.lr,
        weight_decay=1e-4,
    )

    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer,
        T_max=args.epochs,
    )

    print(
        f"Device: {device} | "
        f"Train/Validation/Test: "
        f"{len(train_data)}/{len(valid_data)}/{len(test_data)}"
    )

    print(
        "Training class counts:",
        dict(zip(CLASS_LABELS, class_counts.int().tolist())),
    )

    print(
        "Class weights:",
        [round(weight, 2) for weight in class_weights.tolist()],
    )

    best_state = None
    best_accuracy = -1.0
    start_time = time.time()

    for epoch in range(1, args.epochs + 1):
        net.train()
        running_loss = 0.0

        for images, labels in train_loader:
            optimizer.zero_grad()

            loss = criterion(
                net(images.to(device)),
                labels.to(device),
            )

            loss.backward()
            optimizer.step()

            running_loss += float(loss) * labels.numel()

        scheduler.step()
        validation_accuracy = accuracy(net, valid_loader, device)

        if validation_accuracy >= best_accuracy:
            best_accuracy = validation_accuracy
            best_state = {
                key: value.detach().clone()
                for key, value in net.state_dict().items()
            }

        average_loss = running_loss / max(len(train_data), 1)
        elapsed = time.time() - start_time

        print(
            f"Epoch {epoch:>2}/{args.epochs} | "
            f"Loss: {average_loss:.4f} | "
            f"Validation accuracy: {validation_accuracy:.3f} | "
            f"Elapsed: {elapsed:.0f}s"
        )

    if best_state is None:
        raise SystemExit("Training failed: no valid model state was saved.")

    net.load_state_dict(best_state)

    test_accuracy = accuracy(net, test_loader, device)

    print(
        f"Best validation accuracy: {best_accuracy:.3f} | "
        f"Test accuracy: {test_accuracy:.3f} | "
        f"Total time: {time.time() - start_time:.0f}s"
    )

    output_path = Path(args.out)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    wrapper = ExportWrapper(net).eval()
    dummy_input = torch.zeros(1, SIZE, SIZE, 3)
    export_errors = []

    export_options = [
        {
            "opset_version": 17,
            "input_names": ["image"],
            "output_names": ["scores"],
            "dynamo": False,
        },
        {
            "opset_version": 17,
            "input_names": ["image"],
            "output_names": ["scores"],
        },
        {
            "input_names": ["image"],
            "output_names": ["scores"],
            "dynamo": True,
        },
    ]

    for options in export_options:
        try:
            torch.onnx.export(
                wrapper,
                (dummy_input,),
                str(output_path),
                **options,
            )
            break
        except Exception as error:
            export_errors.append(
                f"{type(error).__name__}: {error}"
            )
    else:
        raise SystemExit(
            "ONNX export failed:\n"
            + "\n".join(export_errors)
            + "\nInstall the required packages, such as onnx or onnxscript."
        )

    try:
        import onnxruntime as ort

        session = ort.InferenceSession(
            str(output_path),
            providers=["CPUExecutionProvider"],
        )

        test_input = np.random.rand(
            1, SIZE, SIZE, 3
        ).astype("float32")

        scores = session.run(
            None,
            {session.get_inputs()[0].name: test_input},
        )[0]

        print(
            "ONNX verification successful:",
            session.get_inputs()[0].shape,
            "->",
            scores.shape,
        )

    except ImportError:
        print(
            "ONNX Runtime is not installed. "
            "Install it to verify the exported model."
        )

    print(f"\nModel exported to: {output_path}")


if __name__ == "__main__":
    main()
