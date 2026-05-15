# Permanent stoplist
#
# Append-only ledger across all bug-hunt-loop runs. Each iter's outcome
# (fixed/filed/dropped/no-red/etc.) goes here so the hunter never re-raises
# a slug we already processed. To "reopen" a slug, manually delete its line.
- iter 1 dropped: reinit-without-settings-retains-stale-settings
- iter 2 fixed: event-notifier-late-event-after-dispose
- iter 3 fixed: service-settings-copywith-cannot-clear-priority
- iter 4 dropped: reentrant-cancel-subscription-remains-live-after-disable
- WONTFIX: service-settings-copywith-cannot-clear-priority (use withClearedPriority(), do not reintroduce the Object? sentinel)
- iter 5 dropped: has-request-handler-ignores-general-handlers-with-identifier
- iter 6 no-red: update-session-settings-unknown-serviceid-partial-state (COMPILE_ERROR)
- iter 7 no-red: dialog-controller-global-service-noop-prune-uses-session-registry (COMPILE_ERROR)
- iter 8 no-red: create-session-logandskip-retains-unknown-service-pin (UNKNOWN)
- iter 9 no-red: update-global-settings-notify-throw-partial-state (UNKNOWN)
- iter 10 green-failed: update-settings-before-init-lateinit-crash (ISSUE-update-settings-before-init-lateinit-crash)
- iter 11 dropped: resolved-registrations-throws-on-disabled-slot
- iter 3 wontfix-rediscovery: service-settings-copywith-cannot-clear-priority (test deleted; bug is WONTFIX, see PACKAGE_ISSUES)
- iter 12 no-red: update-global-settings-notify-throw-partial-state (UNKNOWN)
