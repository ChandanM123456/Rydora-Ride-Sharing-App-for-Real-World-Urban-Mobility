# 🚗 Rydora – Ride-Sharing App for Real-World Urban Mobility

Rydora is a **real-world, production-oriented ride-sharing system** designed with **cost efficiency, scalability, and security** in mind. Unlike typical monolithic ride-hailing apps, Rydora follows a **decoupled architecture** where mobile clients are lightweight and the core intelligence runs in a **Python-based administrative matcher**.

This repository contains the **Passenger App**, **Rider (Driver) App**, and the **Python Admin Matcher** that together form the complete Rydora ecosystem.

---

## 📌 Key Features

* 📍 **High-precision routing & fare estimation** (Passenger)
* 🗺️ **Low-cost real-time navigation** using OpenStreetMap (Rider)
* 🧠 **Centralized Python-based matching engine** (Admin)
* 🔥 **Realtime synchronization via Firebase Firestore**
* 🔐 **Secure matching with OTP-based ride start**
* 📊 **Live analytics & admin controls via Jupyter Notebook**

---

## 🏗️ System Architecture Overview

```
Passenger App (Flutter + GraphHopper)
        |
        v
 Firebase Firestore  <---->  Python Admin Matcher (Jupyter)
        ^
        |
Rider App (Flutter + OpenStreetMap)
```

The mobile apps are **stateless clients**, while all critical logic (matching, validation, overrides) is executed in the **Python Admin layer**.

---

## 🧭 1. Mapping & Routing Strategy

### 👤 Passenger Side – GraphHopper API

Used for **accurate distance calculation and fare estimation**.

**Flow:**

* Passenger selects pickup & destination
* App sends a `GET` request to the **GraphHopper Routing API**
* Response contains:

  * Route polyline
  * Total distance (meters)
  * Weight / duration

**Usage:**

* Draw route on map
* Calculate fare using a `price_per_km` constant

---

### 🚖 Rider Side – OpenStreetMap (OSM)

Optimized for **cost-efficiency and continuous tracking**.

**Implementation:**

* `flutter_map` with OpenStreetMap tiles
* No paid API required

**Functionality:**

* Rider location sampled every **5–10 seconds**
* Location pushed to Firestore `active_riders` collection
* Acts as a **heartbeat** for the matching engine

---

## 🧠 2. Python "Admin" Matcher (Jupyter Notebook)

The **Jupyter Notebook** acts as:

* Matching engine
* Admin dashboard
* Analytics console
* Emergency recovery tool

No separate admin app is required.

---

### A. Ride Matching Loop

The matcher runs continuously using a `while True` loop or Firestore listener.

**Steps:**

1. **Fetch Ride Requests**

   * Query `ride_requests` where `status == "pending"`

2. **Fetch Active Riders**

   * Query `active_riders` where `is_online == true`

3. **Distance Calculation (Haversine)**

```python
def calculate_distance(p1, p2):
    # Haversine formula
    return distance
```

4. **Assignment Logic**

   * Select nearest rider
   * Update Firestore:

     * `rider_id`
     * `status = "matched"`

---

### B. Admin Operations via Python

All admin controls are implemented as **dedicated notebook cells**.

#### 👥 User Management

* Ban / unban users
* Verify drivers
* Inspect profiles

#### 📊 Analytics

* Ride density visualization
* Peak-hour analysis
* Historical demand patterns

> Implemented using `pandas` and `matplotlib`

#### 🔄 System Recovery

* Reset stuck rides
* Clear inactive drivers
* Handle app crash scenarios

---

## 🔁 3. Data Flow Architecture

| Component     | Technology            | Responsibility                                |
| ------------- | --------------------- | --------------------------------------------- |
| Passenger App | Flutter + GraphHopper | Route preview, fare estimate, ride request    |
| Rider App     | Flutter + OSM         | Live tracking, navigation                     |
| Database      | Firebase Firestore    | Real-time state sync                          |
| Logic Layer   | Python (Jupyter)      | Matching, lifecycle management, admin control |

---

## ⚡ 4. Technical Advantages

### 🔐 Decoupled & Secure

* Matching logic is **not exposed** in mobile apps
* Users cannot manipulate rider selection

### 💰 Cost Optimized

* OSM used for high-frequency driver tracking
* Paid APIs used **only where precision matters**

### 🧪 Admin Flexibility

* Live code execution
* No redeployment needed for new reports or fixes

---

## 🔒 5. Security & Authentication

### 🔑 Firestore Security Rules

* Passengers: can create ride requests
* Python Admin (Service Account):

  * Only entity allowed to assign `rider_id`

### 🔢 OTP-Based Ride Start

* Python Admin generates a **4-digit OTP** on match
* Driver must enter OTP to begin the trip
* Prevents fake or accidental ride starts

---

# 🚀 Setup & Execution Manual

## 1. Prerequisites

### Software Requirements

* **Flutter SDK** (latest stable)
* **Python 3.10+**
* **Jupyter Notebook / Jupyter Lab**
* **Firebase CLI / Console Access**

### API Keys & Accounts

* Firebase Project
* GraphHopper API Key
* OpenStreetMap (no key required)

---

## 2. Environment Setup

### A. Mobile Apps (Passenger & Rider)

#### Clone Repository

```bash
git clone https://github.com/ChandanM123456/Rydora-Ride-Sharing-App-for-Real-World-Urban-Mobility
```

#### Firebase Configuration

* Download:

  * `google-services.json` (Android)
  * `GoogleService-Info.plist` (iOS)
* Place in:

  * `android/app/`
  * `ios/Runner/`

#### Install Dependencies

```bash
cd rydora_passenger && flutter pub get
cd ../rydora_rider && flutter pub get
```

#### Configure GraphHopper

Edit `lib/core/constants.dart`:

```dart
const String graphHopperKey = 'YOUR_KEY_HERE';
```

---

### B. Python Admin Matcher (Jupyter)

#### Install Dependencies

```bash
pip install firebase-admin pandas matplotlib ipywidgets
```

#### Firebase Service Account

* Firebase Console → Project Settings → Service Accounts
* Generate new private key
* Save as `serviceAccountKey.json`

---

## 3. Running the System (Startup Order)

### Step 1: Start Admin Matcher

```bash
jupyter lab
```

* Open `admin_matcher.ipynb`
* Run **Initialization Cell**
* Run **Matching Loop Cell**

---

### Step 2: Launch Rider App

```bash
cd rydora_rider && flutter run
```

* Log in as driver
* Toggle **Go Online**

---

### Step 3: Launch Passenger App

```bash
cd rydora_passenger && flutter run
```

* Select destination
* View route & fare
* Click **Request Ride**

---

## 4. Monitoring the Workflow

| Action       | Where to Monitor              |
| ------------ | ----------------------------- |
| Ride Request | `ride_requests` collection    |
| Matching     | Jupyter logs                  |
| Active Trip  | Rider App UI                  |
| Completion   | `historical_rides` collection |

---

## 🛠️ 5. Troubleshooting

### ❌ No Drivers Found

* Ensure driver exists in `active_riders`
* `is_online == true`

### 🗺️ Map Not Loading

* Check internet
* Verify OSM `urlTemplate`

### 🔐 Permission Denied

* Confirm Service Account has **Editor / Owner** role

---

## 🌍 Real‑World Problem Statement

Urban mobility today faces several critical challenges:

* ❌ Inefficient rider–passenger matching causing long wait times
* ❌ High dependency on expensive proprietary map APIs
* ❌ Centralized logic inside mobile apps, making systems vulnerable to manipulation
* ❌ Lack of flexibility for admins to monitor, intervene, or analyze ride data in real time
* ❌ Poor scalability for academic or early‑stage startup implementations

**Rydora is designed to solve these exact real‑world issues** using a clean, modular, and cost‑efficient architecture.

---

## 🚦 What Problem Does Rydora Solve?

Rydora addresses **real urban ride‑sharing problems** by separating responsibilities across three layers:

### 1️⃣ Fair & Transparent Ride Matching

Instead of embedding ride‑matching logic inside the mobile app (which users can reverse‑engineer or manipulate), Rydora:

* Executes matching in a **secure Python Admin engine**
* Uses **geographical distance (Haversine)** for fair driver assignment
* Ensures passengers always get the **nearest available rider**

This mirrors how **real ride‑hailing companies** isolate core algorithms from clients.

---

### 2️⃣ Cost‑Effective Mapping Strategy

Commercial ride apps spend heavily on map APIs. Rydora minimizes cost by:

* Using **GraphHopper only for passengers**, where accurate routing and pricing matter
* Using **OpenStreetMap (OSM)** for riders, where frequent updates would otherwise be expensive

➡️ This hybrid strategy makes Rydora **startup‑friendly and scalable**.

---

### 3️⃣ Real‑Time Urban Mobility Tracking

Rydora continuously tracks:

* Rider availability
* Rider movement (heartbeat every 5–10 seconds)
* Ride lifecycle stages

This enables:

* Faster pickups
* Better city‑level mobility insights
* Real‑time decision making

---

## 🧠 Why the Python Admin Engine Matters (Real‑World Design)

Most student projects ignore admin control. Rydora treats it as a **first‑class system component**.

### Admin Engine Capabilities:

* 🔄 Live ride matching without redeploying apps
* 👥 Driver verification & banning
* 📊 Demand & peak‑hour analytics
* 🛑 Emergency ride reset in crash scenarios

Using **Jupyter Notebook** allows admins to:

* Write new logic instantly
* Run diagnostics on live data
* Perform safe system overrides

This closely resembles **operations dashboards used by real ride‑sharing companies**.

---

## 🔐 Security‑First Architecture

Rydora enforces strong backend control:

* 🔒 Firestore rules prevent riders or passengers from self‑assigning rides
* 🔑 Only the Admin service account can modify critical fields like `rider_id`
* 🔢 OTP‑based ride start ensures physical rider‑passenger verification

These measures reduce:

* Fake ride starts
* Data tampering
* Unauthorized access

---

## 📊 Data‑Driven Urban Insights

Because all ride data flows through Firestore and Python:

* Ride density maps can be generated
* Peak demand hours can be analyzed
* City‑wise expansion decisions can be simulated

This makes Rydora useful not only as an app, but also as a **mobility analytics platform**.

---

## 🧪 Academic & Industry Relevance

Rydora is suitable for:

* 🎓 Final‑year / capstone projects
* 🚀 Startup MVPs
* 🧩 System‑design interviews
* 📱 Flutter + Firebase case studies

It demonstrates real‑world concepts such as:

* Distributed systems
* Secure backend‑controlled logic
* Geo‑spatial computation
* Cost‑aware API design
* Admin‑driven orchestration

---

## 🔮 Future Enhancements

Planned or easily extendable features:

* AI‑based demand prediction
* Dynamic surge pricing
* Ride pooling / shared rides
* In‑app payments
* Driver rating & fraud detection



📬 Contact

Project Author:
Name: Chandan M
Email: chandan.chandu0608@gmail.com
