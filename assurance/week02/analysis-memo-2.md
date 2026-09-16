# Analysis Memo 2

CPS 5981 01, Week 02 — 10 points, two pages maximum

## As a vulnerability

The finding: the application sends no Content-Security-Policy header on any response, so a page places no restriction on which scripts are allowed to run in it.
Named as: Content Security Policy (CSP) Header Not Set — CWE-693, Protection Mechanism Failure. ZAP rated it Medium risk at High confidence, on 5 URLs.

## As a risk

If someone can get text of their own choosing onto a page another customer opens — the review form is one such place, then that text runs with the same standing as the shop's own code, inside the other customer's signed-in session, and afterwards the shop cannot tell what that customer did from what was done through them.

## Which one goes in front of the manager, and why

The two versions are not competing descriptions of the same fact. They answer different questions, and which one belongs in front of a manager depends entirely on the decision that manager is about to make.

Say the manager is the engineering lead who decides what goes into the next two-week sprint, and this finding is competing with four other items for the same time.

For that decision, the risk version goes first. The vulnerability version — "the application sends no Content-Security-Policy header, CWE-693, five URLs" — is true, precise, and gives that manager nothing to compare against the other four items. It does not say what happens if it is left alone, so the only way to rank it is by the scanner's severity label, and "Medium" is a judgment the scanner made without knowing anything about this shop, what it sells, or what its customers would lose. The risk version states what is at stake in terms the manager is already weighing: a customer's order may not be theirs, and afterwards nobody can tell which orders were genuine. That can be set against the other four items. "Medium" cannot.

The risk version is not sufficient on its own, and I would not send it alone. Whoever picks the work up cannot act on "we can no longer show which orders were genuine." They need the header name, the five URLs and the CWE. So the memo leads with the risk and attaches the vulnerability — not because one is for managers and the other for engineers, but because one supports the decision to act and the other supports the act itself.

I want to be explicit that "managers get risk, engineers get vulnerabilities" is the answer I am not giving. It is a rule about job titles, and it fails as soon as the manager's decision changes. If the same lead had already accepted this risk last quarter and was now choosing between two proposed fixes, the risk version would tell them nothing they did not already know, and the vulnerability version — which URLs, what the header actually governs, whether a report-only policy would be enough to start — would be the useful one. Same finding, same manager, opposite answer, because the decision moved.

### What would change my mind

**If the finding were not confirmed.** I am comfortable leading with the risk framing partly because I verified this one myself, without the scanner, by reading the response headers by hand during the threat modelling exercise. If the scan were my only evidence, the manager's first question would rightly be "is this real, or is it a tool being cautious?" — and a risk statement built on an unverified finding invites a decision that cannot be supported. In that case I would lead with the vulnerability version and say plainly that confirmation is the next step.

**If the injection path turned out not to exist.** My risk statement opens with *if someone can get text of their own choosing onto a page another customer opens*. I have not established that. If customer text is escaped everywhere it is rendered, the consequence I described does not follow, and presenting it to a manager as a likely outcome would have been wrong. The honest version of this memo is that I am reporting a missing protection with high confidence and a consequence with considerably less.

**If the deployment already had the header added upstream.** The scan ran against the application directly. A proxy or CDN in front of it could supply the header, which would make this a finding about my test configuration rather than about what customers actually receive. One look at a response from the real deployment settles that, and it would move the finding from a decision to a non-issue.

## What I am not sure about

The scan establishes that the header is absent, not that anything can be injected. Those are different claims and only the first one is measured. I never submitted a review with a marker string, so I have not confirmed the shop renders customer text unescaped, and I never read the Set-Cookie line, so I do not know whether the session cookie is reachable from script at all. That flag is the difference between a page running unexpected script and an account being taken over, and I cannot tell you which of those I am reporting. I also scanned a deliberately vulnerable application on my own machine with nothing in front of it; a real deployment may sit behind a proxy that adds the header, in which case the finding is about this configuration and not about the software. Finally, CWE-693 is a broad category rather than a specific defect — it names a protection that is missing, not a way in
