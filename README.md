CacaoGrade AI
Cacao Bean Fermentation Stage Classification and Quality Assessment System
CacaoGrade AI is a web-based system that uses a Convolutional Neural Network (CNN) to help assess cacao bean fermentation stages from uploaded images. It includes a Flutter web application, a FastAPI backend, a CNN inference service, and a PostgreSQL database.
Group Members
Rico D. Respecia
Ashley C. Cuarenta
Princess Ivony P. Castillo
Technology Stack
Component	Technology
Frontend	Flutter Web, Dart
Backend API	FastAPI, Python
CNN Service	FastAPI, Python
Database	PostgreSQL
API Server	Uvicorn
Authentication	JWT
Image Processing	Pillow, NumPy
Project Structure
Cacao/
├── backend/                  # Main API and authentication
├── cnn_service/              # CNN inference service
├── certs/                    # Local TLS certificates
├── database/
│   ├── migrations/            # SQL database migrations
│   └── README.md
├── docs/
│   ├── README.md
│   ├── api.md
│   └── architecture.md
├── frontend/
│   ├── assets/
│   ├── lib/
│   │   ├── constants/
│   │   ├── models/
│   │   ├── providers/
│   │   ├── reports/
│   │   ├── routes/
│   │   ├── screens/
│   │   ├── services/
│   │   └── widgets/
│   ├── test/
│   └── README.md
├── .env.example
├── .gitignore
├── RUN.bat
├── RUN_CNN.bat
├── RUN_FLUTTER.bat
├── RUN_SSL.bat
├── RUN_CNN_SSL.bat
├── RUN_FLUTTER_SSL.bat
└── README.md

Requirements
Install the following before running the project:
Python compatible with the project's dependencies
Flutter SDK
Google Chrome
PostgreSQL
Git
Make sure Flutter and Python are available from your terminal. PostgreSQL must be running and the database connection must be configured before starting the backend.
Configuration
The project uses environment variables from a root-level .env file.
Create your local environment file in PowerShell:
Copy-Item .env.example .env

Edit .env if your local PostgreSQL username, password, database, or service URLs differ from the defaults.
Important variables:
Variable	Purpose
API_BASE_URL	Base URL of the backend API
DATABASE_URL	PostgreSQL connection string
CNN_SERVICE_URL	CNN prediction endpoint
JWT_SECRET	Optional JWT signing key; generated locally if unset
CLOUD_STORAGE_BUCKET	Optional cloud storage configuration
The default local service URLs are:
Backend: http://127.0.0.1:8000
CNN service: http://127.0.0.1:8001
Do not commit .env, private keys, generated secrets, or other sensitive configuration.
Database Setup
Install and start PostgreSQL.
Create the cacao_gradeai database and configure the credentials in .env.
Apply the database migration using psql:
psql $env:DATABASE_URL -f .\database\migrations\0001_init.sql
If your PostgreSQL installation does not recognize psql in PowerShell, use the PostgreSQL SQL Shell or provide the full path to psql.exe.
For additional schema information, see database/README.md.
Install Backend Dependencies
Open PowerShell in the project root:
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
cd ..

Install CNN Service Dependencies
From the project root:
cd cnn_service
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
cd ..

The CNN service also needs the appropriate trained model files for inference. Check cnn_service/model/README.md for model placement and requirements.
Run the System
Use three separate terminal windows. Start each service and leave its terminal running.
1. Start the CNN service
Double-click RUN_CNN.bat, or run:
.\RUN_CNN.bat

The service uses port 8001.
2. Start the backend API
Double-click RUN.bat, or run:
.\RUN.bat

The backend uses port 8000.
API documentation:
http://127.0.0.1:8000/docs
Health check:
http://127.0.0.1:8000/health
3. Start the Flutter web app
Double-click RUN_FLUTTER.bat, or open another terminal and run:
cd frontend
flutter pub get
flutter run -d chrome --dart-define=CACAO_API=http://127.0.0.1:8000

The frontend requires Flutter and Chrome. See frontend/README.md for more details.
HTTPS Development Setup
The repository includes separate launch scripts for HTTPS:
RUN_CNN_SSL.bat
RUN_SSL.bat
RUN_FLUTTER_SSL.bat
Generate a local development certificate if needed. From the project root:
cd backend
.\.venv\Scripts\python.exe make_cert.py
cd ..

Then start the CNN service, backend, and Flutter client using their respective SSL scripts.
The development certificate is self-signed and intended for local testing. Do not use it as a production certificate.
Documentation
docs/README.md — documentation index and environment configuration
docs/api.md — API endpoints, responses, and authorization rules
docs/architecture.md — system architecture and component responsibilities
database/README.md — database schema and migration details
frontend/README.md — Flutter application setup
cnn_service/model/README.md — CNN model files
Security Notes
Keep .env and private signing keys out of version control.
Use a strong, unique JWT signing key in shared or deployed environments.
Use HTTPS with a trusted certificate when deploying publicly.
Configure PostgreSQL credentials securely.
Do not expose development credentials or test accounts in a public deployment.
Troubleshooting
The backend cannot connect to PostgreSQL
Check that PostgreSQL is running, the database exists, and DATABASE_URL contains the correct connection details.
The CNN service cannot make predictions
Check that its dependencies are installed, the required model files are available, and the service is running on port 8001.
Flutter cannot connect to the backend
Check that the backend is running and that CACAO_API points to the correct backend URL.
Flutter is not recognized
Install Flutter, add its bin directory to the system PATH, and open a new terminal.
---
This project was developed for academic purposes. Configure credentials, certificates, and service URLs appropriately before deployment.

- docs/README.md — Documentation index and environment configuration
- docs/api.md — API endpoints, responses, and authorization rules
- docs/architecture.md — System architecture and component responsibilities
- database/README.md — Database schema and migration details
- frontend/README.md — Flutter application setup
- cnn_service/model/README.md — CNN model files