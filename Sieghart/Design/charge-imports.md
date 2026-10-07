# Actual charge imports

Open **AI agents → Tokens, charges & connections → Prices & recorded charges**. Choose **Import CSV / JSON** and review the new charges and provider/currency totals. Save with **Import charges**; Cancel saves nothing. Template downloads a CSV example; Export saves all recorded charges as versioned JSON.

These are actual charges copied from a statement or invoice. API-equivalent token estimates never become charges automatically. This adapter reads a selected file; it does not sign in to a billing account or parse invoice PDFs.

## CSV

UTF-8, optionally with a BOM. Use these six columns in this order:

```csv
reference,provider,date,amount,currency,kind
invoice-001,codex,2026-10-01,20.00,USD,Subscription
invoice-002,claude,2026-10-02,12.50,BRL,API
```

Quoted commas and escaped quotes are supported. References cannot contain control characters. Use a stable invoice or payment identifier per provider. The two providers may have the same reference independently.

## JSON

```json
{
  "version": 1,
  "charges": [
    {
      "reference": "invoice-001",
      "provider": "codex",
      "date": "2026-10-01",
      "amount": "20.00",
      "currency": "USD",
      "kind": "Subscription"
    }
  ]
}
```

- Providers: `codex`, `claude`. Currencies: `USD`, `BRL`. Types: `Subscription`, `API`.
- Dates: valid `YYYY-MM-DD` or ISO 8601 timestamps. Date-only invoices are anchored to noon on the local billing day, preserving the month in local monthly totals. Export uses dated ISO timestamps.
- Amount is a string with a decimal point, up to eight decimal places, positive and below one billion. Values are stored as Decimal. Refund/credit imports are not supported by this positive-charge ledger.
- Maximum 2 MiB and 5,000 entries per import. All rows validate before review. One invalid row or conflicting reference rejects the entire batch.
- The same provider/reference and values are skipped on reimport. A changed amount/date/currency/type under that reference is a conflict. Correct/remove the existing charge deliberately before importing a replacement.
- JSON export assigns stable references to manual charges, so importing your own export does not duplicate them. Provider, date, amount, currency, type and import source are retained locally; no file or charge data is uploaded.
