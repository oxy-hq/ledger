# Setup

Ledger is a Flutter app that renders a CRUD UI from YAML schemas (in
[`~/repos/ledger-schemas`](../ledger-schemas)) and persists records to a Google
Sheets workbook via a GCP service account.

You only need to do this setup once.

## 1. Create the Google Sheet

1. Create a new Google Sheets workbook (or use an existing one).
2. Copy the spreadsheet ID from the URL — the long string between `/d/` and
   `/edit` in `https://docs.google.com/spreadsheets/d/<ID>/edit`.
3. You can leave the workbook empty; the app will create a tab per view on
   first run.

## 2. Create a GCP service account

1. Go to <https://console.cloud.google.com/> and create (or pick) a project.
2. Enable the Google Sheets API for that project:
   <https://console.cloud.google.com/apis/library/sheets.googleapis.com>
3. Go to **IAM & Admin → Service Accounts**, click **Create Service Account**.
   - Name: `ledger-app` (or anything)
   - Role: leave blank — the service account only needs sheet-level access,
     granted in the next step.
4. Open the new service account, go to the **Keys** tab, **Add Key → Create
   New Key → JSON**. Save the downloaded file as:

       ~/.config/ledger/service-account.json

5. Copy the service account's email address (looks like
   `ledger-app@<project>.iam.gserviceaccount.com`).

## 3. Share the sheet with the service account

In the Google Sheet from step 1, click **Share** and grant **Editor** access
to the service account email. (Uncheck "Notify people" — it can't receive
email.)

## 4. Write the app config

Write `~/.config/ledger/config.yaml`:

```yaml
schemas_dir: /Users/<you>/repos/ledger-schemas/views
service_account_key_path: /Users/<you>/.config/ledger/service-account.json
spreadsheet_id: <ID from step 1>
```

## 5. Run the app

```bash
cd ~/repos/ledger
flutter run -d macos
```

On first launch the app will create one sheet tab per view and write a header
row. Add a row through the app to confirm it round-trips.
