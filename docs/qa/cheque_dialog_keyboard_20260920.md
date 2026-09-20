# Cheque entry dialog: mobile save action

Date: 2026-09-20
Base: cdf76f7189426221f69a956bfd34205b4edc6699
Isolated branch: fix/cheque-dialog-keyboard-20260920
Target source: F:\YALLAH_ACCOUNTS_LATEST_CLEAN_20260920

## Reproduction and repair
The shared ChequeStepEntry dialog placed its complete form and save button in
an unscrollable Column. Phone stacking and keyboard insets pushed save outside
the dialog. The baseline iPhone 414x896 / keyboard 330 test failed with a
160-pixel bottom overflow and an untappable save button.
The title and fields now occupy a bounded, flexible scroll viewport, while the
save action remains outside that viewport. Compact insets also cover landscape.
Field controllers are disposed and focus is released after valid submission.
The existing validation, draft payload, amount, and posting services are unchanged.

## Verification
- 12 new widget tests passed: small phone, iPhone, Arabic 1.5x text, landscape,
  desktop, keyboard visibility, scrolling, required validation, draft return,
  and preservation of entered values across keyboard changes.
- Combined run: 28 passed, 0 failed (also voucher phone UI and received/issued cheque regressions).
- Full flutter analyze --no-pub: no issues found.
- Evidence logs: EVIDENCE/CHEQUE_DIALOG_20260920/ in the isolated worktree.
- Financial tests used disposable temporary databases; owner data was not edited.

## Delivery boundary
This is a tested source fix, not a newly installed application. No IPA was built,
no remote branch was pushed, and no live iPhone acceptance was claimed.
A subsequent iOS build must include this fix; previously built IPA files do not.
