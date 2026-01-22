#!/usr/bin/env python3
"""
Realtime Driver Proposal Status Manipulator
-------------------------------------------
Safely updates 'status' field in driver_proposals collection from Python,
with retry + exponential backoff to bypass Firebase console quota limits.

Usage examples:
    python proposal_status_updater.py --proposal_id aRI2ujS0Q9Ax1QTsu40Q --status accepted
    python proposal_status_updater.py --status pending_acceptance --all
"""

import time
import argparse
import logging
from datetime import datetime
from typing import Optional

import firebase_admin
from firebase_admin import credentials, firestore
from google.api_core.exceptions import GoogleAPICallError, ResourceExhausted

# ------------------- CONFIG -------------------
SERVICE_ACCOUNT_PATH = "path/to/driver_app_service_account.json"  # 🔁 change this
MAX_RETRIES = 10
INITIAL_BACKOFF = 2.0  # seconds

# ------------------- LOGGING -------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

# ------------------- FIRESTORE INIT -------------------
def init_firestore() -> firestore.Client:
    try:
        app = firebase_admin.get_app("driver_app")
    except ValueError:
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        app = firebase_admin.initialize_app(cred, name="driver_app")
        logging.info("✅ Firestore initialized for driver_app")
    return firestore.client(app)

# ------------------- HELPER: SAFE UPDATE -------------------
def safe_update(doc_ref, data: dict):
    """Update with retry + exponential backoff for quota/network errors"""
    backoff = INITIAL_BACKOFF
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            doc_ref.update(data)
            logging.info(f"✅ Updated {doc_ref.id} with {data}")
            return True
        except ResourceExhausted:
            logging.warning(f"[{attempt}/{MAX_RETRIES}] Quota exceeded — retrying in {backoff:.1f}s")
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)
        except GoogleAPICallError as e:
            logging.error(f"[{attempt}/{MAX_RETRIES}] API Error: {e}")
            time.sleep(backoff)
        except Exception as e:
            logging.error(f"[{attempt}/{MAX_RETRIES}] Unexpected Error: {e}")
            time.sleep(backoff)
    logging.error(f"❌ Failed to update {doc_ref.id} after {MAX_RETRIES} retries.")
    return False

# ------------------- MAIN LOGIC -------------------
def update_single_status(db, proposal_id: str, new_status: str):
    """Update a specific proposal's status"""
    doc_ref = db.collection("driver_proposals").document(proposal_id)
    data = {"status": new_status, "last_updated": datetime.utcnow()}
    safe_update(doc_ref, data)

def bulk_update_status(db, new_status: str, limit: Optional[int] = None):
    """Bulk update all proposals or limited number"""
    logging.info(f"🔄 Bulk updating driver_proposals to status '{new_status}' ...")
    query = db.collection("driver_proposals").where("status", "!=", new_status)
    if limit:
        query = query.limit(limit)
    docs = query.stream()
    count = 0
    for doc in docs:
        doc_ref = doc.reference
        data = {"status": new_status, "last_updated": datetime.utcnow()}
        if safe_update(doc_ref, data):
            count += 1
    logging.info(f"✅ Bulk update complete — {count} documents modified.")

# ------------------- REALTIME WATCHER -------------------
def watch_driver_proposals(db):
    """Listen for driver_proposals changes in real time."""
    def on_snapshot(docs, changes, read_time):
        for change in changes:
            if change.type.name == "ADDED":
                logging.info(f"[NEW] Proposal {change.document.id} added: {change.document.to_dict().get('status')}")
            elif change.type.name == "MODIFIED":
                logging.info(f"[MODIFIED] Proposal {change.document.id} → {change.document.to_dict().get('status')}")
            elif change.type.name == "REMOVED":
                logging.info(f"[REMOVED] Proposal {change.document.id}")

    logging.info("👂 Listening for driver_proposals changes ... (Ctrl+C to exit)")
    db.collection("driver_proposals").on_snapshot(on_snapshot)

# ------------------- CLI -------------------
def main():
    parser = argparse.ArgumentParser(description="Driver Proposal Status Manipulator")
    parser.add_argument("--proposal_id", help="Specific proposal document ID")
    parser.add_argument("--status", required=True, help="New status to set")
    parser.add_argument("--all", action="store_true", help="Update all proposals")
    parser.add_argument("--listen", action="store_true", help="Start realtime listener only")
    args = parser.parse_args()

    db = init_firestore()

    if args.listen:
        watch_driver_proposals(db)
        while True:
            time.sleep(1)

    elif args.all:
        bulk_update_status(db, args.status)

    elif args.proposal_id:
        update_single_status(db, args.proposal_id, args.status)

    else:
        logging.error("❌ Must specify either --proposal_id or --all or --listen")

if __name__ == "__main__":
    main()
