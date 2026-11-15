"""Fathom Mail: new-mail notifications for the Fathom desktop.

Each mail service is a provider class with login(say), logout() and
poll(cursor, focused_only) -> (new messages, unread count, next cursor).
Add one by writing a module like outlook.py and listing it here."""

from .outlook import Outlook

PROVIDERS = {Outlook.kind: Outlook}
