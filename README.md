# Food Management & Waste Reduction App

This is a smart, Flutter-based mobile application designed to help users manage their food consumption, reduce waste, and make more environmentally conscious decisions. By leveraging AI-driven features like OCR scanning and barcode recognition, the app simplifies inventory tracking and impact assessment.

## 🚀 Key Features

- **Inventory Management**: Keep track of your food items with ease.
- **Smart Scanning (OCR & Barcode)**: 
  - Scan grocery receipts or labels using **Google ML Kit Text Recognition**.
  - Identify products instantly with **ML Kit Barcode Scanning** and the **Open Food Facts API**.
- **Waste Dashboard**: Visualize your food waste impact through interactive charts (powered by `fl_chart`) and impact factors.
- **AI Chatbot**: Get tips on food preservation and recipes through the built-in AI assistant.
- **Firebase Integration**: 
  - Secure **Authentication** (Email & Google Sign-In).
  - Real-time data synchronization with **Cloud Firestore**.
- **Nutritional Insights**: Fetch product data to stay informed about what you consume.
- **Smart Notifications**: Reminders to consume food before it expires.

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev/)
- **State Management**: Provider & Riverpod
- **Backend**: Firebase (Auth, Firestore)
- **AI/ML**: Google ML Kit (Text Recognition, Barcode Scanning, Document Scanner)
- **Database (Local)**: SQLite (`sqflite`) for offline storage.
- **Charts**: `fl_chart`
- **APIs**: Open Food Facts

## 📦 Components & Structure

- `lib/features/ocr_scan`: Logic for receipt and label processing.
- `lib/features/chatbot`: Interactive AI support for sustainable living.
- `lib/waste_dashboard`: Analytics and visualization of consumption patterns.
- `lib/services`: Integration with external APIs and Firebase.

## 🏁 Getting Started

### Prerequisites

- Flutter SDK (latest version recommended)
- Firebase Account & Project

### Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/henilpatel08/Food-Management-App.git
   cd Food-Management-App
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Firebase Configuration**:
   - Since project credentials are kept private for security, you need to configure your own Firebase project.
   - Install the FlutterFire CLI.
   - Run `flutterfire configure` to generate your own `lib/firebase_options.dart`.

4. **Environment Variables**:
   - Create a `assets/keys.env` file if required for specialized API keys (like Gemni/OpenAI for the chatbot).

5. **Run the app**:
   ```bash
   flutter run
   ```

## 📄 License

This project is for personal storage and educational purposes. See individual files for licensing details where applicable.

---
*Built with ❤️ for a more sustainable future.*
