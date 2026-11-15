"""Outlook.com (and other Microsoft accounts) through Microsoft Graph.

Signs in with the device-code flow against your own app registration (its
client ID lives in ~/.config/fathom/mail.json; it isn't a secret). The
refresh token goes in the GNOME keyring. Reads only: Mail.Read."""

import datetime
import time
import webbrowser

from . import core

AUTH = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
GRAPH = "https://graph.microsoft.com/v1.0"
SCOPES = "offline_access User.Read Mail.Read"
INBOX = "https://outlook.live.com/mail/0/inbox"
LINK_HOSTS = {"outlook.live.com", "outlook.office.com", "outlook.office365.com"}
SELECT = "id,subject,from,receivedDateTime,isRead,bodyPreview,webLink,inferenceClassification"


def _iso(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _epoch(iso):
    try:
        return int(datetime.datetime.fromisoformat(str(iso).replace("Z", "+00:00")).timestamp())
    except ValueError:
        return 0


class Outlook:
    kind = "outlook"
    name = "Outlook"
    inbox_link = INBOX

    def __init__(self, account):
        self.account = account
        self.client_id = account.get("clientId", "")
        self._access = None
        self._expires = 0

    @property
    def label(self):
        return self.account.get("email") or self.account.get("label") or self.name

    # ------------------------------------------------ signing in

    def login(self, say):
        """Device-code sign-in. Returns the account's address."""
        if not self.client_id:
            raise core.MailError("This account has no client ID; add it again with --client-id")
        start = core.request("POST", f"{AUTH}/devicecode", form={"client_id": self.client_id, "scope": SCOPES})
        url = start.get("verification_uri", "https://www.microsoft.com/link")
        say(f"To sign in, open {url} and enter the code {start.get('user_code', '?')}")
        try:
            webbrowser.open(url)
        except Exception:
            pass
        interval = int(start.get("interval", 5))
        deadline = time.time() + int(start.get("expires_in", 900))
        while time.time() < deadline:
            time.sleep(interval)
            try:
                tokens = core.request("POST", f"{AUTH}/token", form={
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "client_id": self.client_id,
                    "device_code": start["device_code"],
                })
            except core.HttpError as e:
                err = e.json().get("error")
                if err == "authorization_pending":
                    continue
                if err == "slow_down":
                    interval += 5
                    continue
                if err in ("authorization_declined", "access_denied"):
                    raise core.MailError("Sign-in was declined") from None
                if err == "expired_token":
                    break
                raise core.MailError(f"Sign-in failed: {e.json().get('error_description', err)}"[:300]) from None
            self._keep(tokens)
            me = self._get(f"{GRAPH}/me?$select=mail,userPrincipalName")
            return core.plain(me.get("mail") or me.get("userPrincipalName") or "", 120)
        raise core.MailError("The sign-in code expired; try again")

    def logout(self):
        core.secret_clear(self.account["id"])

    def _keep(self, tokens):
        self._access = tokens.get("access_token")
        self._expires = time.time() + int(tokens.get("expires_in", 3600)) - 120
        if tokens.get("refresh_token"):
            core.secret_set(self.account["id"], f"Fathom mail ({self.name})", tokens["refresh_token"])

    def _token(self):
        if self._access and time.time() < self._expires:
            return self._access
        refresh = core.secret_get(self.account["id"])
        if not refresh:
            raise core.SignedOut("Not signed in")
        try:
            tokens = core.request("POST", f"{AUTH}/token", form={
                "grant_type": "refresh_token",
                "client_id": self.client_id,
                "refresh_token": refresh.strip(),
                "scope": SCOPES,
            })
        except core.HttpError as e:
            if e.json().get("error") in ("invalid_grant", "interaction_required", "invalid_client"):
                raise core.SignedOut("Microsoft wants you to sign in again") from None
            raise
        self._keep(tokens)
        return self._access

    def _get(self, url):
        for attempt in (1, 2):
            try:
                return core.request("GET", url, headers={"Authorization": f"Bearer {self._token()}"})
            except core.HttpError as e:
                if e.status == 401 and attempt == 1:
                    self._access = None
                    continue
                if e.status == 401:
                    raise core.SignedOut("Microsoft wants you to sign in again") from None
                raise core.MailError(f"Outlook answered with an error ({e.status})") from None
        raise core.MailError("Outlook didn't answer")

    # ------------------------------------------------ reading

    def poll(self, cursor, focused_only=True):
        """New mail since the cursor, the unread count and the next cursor.
        The first poll only sets the cursor: mail already there isn't new."""
        unread = int(self._get(f"{GRAPH}/me/mailFolders/inbox?$select=unreadItemCount").get("unreadItemCount", 0))
        since = cursor.get("since")
        seen = list(cursor.get("seen", []))
        if not since:
            return [], unread, {"since": core.now(), "seen": []}

        url = (f"{GRAPH}/me/mailFolders/inbox/messages?$select={SELECT}"
               f"&$filter=receivedDateTime ge {_iso(since)}&$orderby=receivedDateTime desc&$top=25")
        items = self._get(url.replace(" ", "%20")).get("value", [])
        messages = []
        newest = since
        for item in items if isinstance(items, list) else []:
            if not isinstance(item, dict):
                continue
            mid = str(item.get("id", ""))
            received = _epoch(item.get("receivedDateTime"))
            newest = max(newest, received)
            if not mid or mid in seen:
                continue
            seen.append(mid)
            if item.get("isRead"):
                continue
            if focused_only and item.get("inferenceClassification") == "other":
                continue
            sender = item.get("from")
            sender = sender.get("emailAddress") if isinstance(sender, dict) else None
            sender = sender if isinstance(sender, dict) else {}
            messages.append({
                "id": mid,
                "sender": core.plain(sender.get("name") or sender.get("address") or "", 80),
                "address": core.plain(sender.get("address") or "", 120),
                "subject": core.plain(item.get("subject") or "", 200),
                "preview": core.plain(item.get("bodyPreview") or "", 200),
                "received": received,
                "link": core.safe_link(item.get("webLink"), LINK_HOSTS),
            })
        messages.sort(key=lambda m: m["received"])
        return messages, unread, {"since": newest, "seen": seen[-300:]}
