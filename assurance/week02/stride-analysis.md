# STRIDE analysis

Threat Model v1.0 — CPS 5981 01, Week 02

A category recorded as _checked, nothing found_ is a claim about the search, not about the
system. It is evidence and it is marked as such. A row left blank is not.

## Customer (external entity, User's browser)

| Category | Result |
| --- | --- |
| Spoofing | **Applies** — pretending to be someone else |
| Tampering | Checked, nothing found |
| Repudiation | Checked, nothing found |
| Information disclosure | Checked, nothing found |
| Denial of service | Checked, nothing found |
| Elevation of privilege | Checked, nothing found |

**What I found, and what I looked for and did not find:** what I found when I registered an account was, the registered became protected by a password. The password form accepted five characters, plus a security-question I had to answer. So, this customer can be impersonated by whoever guesses either one, and the recovery secret can never be rotated even after it is known to be expose. Both of those I read off the registration. what I looked for and did not find was I did not confirm anything about the token that actually carries the customer's identity after sign-in. I never read the Set-Cookie line, so I do not know whether the token is reachable from script running in the page. I also found nothing in the customer interface that shows a customer their own sign-in or order history, which is what a customer would need to dispute an action taken in their name; this could be on the server-side but I never looked at any server-side log, so I am not claiming no record exists, only that I did not see one.

## Web application (process, Application server)

| Category | Result |
| --- | --- |
| Spoofing | Checked, nothing found |
| Tampering | Checked, nothing found |
| Repudiation | Checked, nothing found |
| Information disclosure | **Applies** — seeing what they should not |
| Denial of service | Checked, nothing found |
| Elevation of privilege | Checked, nothing found |

**What I found, and what I looked for and did not find:** For the web application, I found that no Content-Security-Policy header is sent. I checked it by hand with command 3 and read the whole response, and the header is absent. So, the page puts no restriction on which scripts are allowed to run in it. This is also the same page which the application renders text other customers wrote, and the same page that holds the session cookie. I also saw that searching "apple" returned "Pineapple Juice", which could mean my typed text is carried into a server-side lookup doing substring matching rather than being filtered in the browser. what I looked for and didn't find was submitting something into the reviews, so i cant confirm that customers text is rendered unescaped. The missing header is exposure, not proof of injection. I also didn't see a single request leave the page so I can't say the server recalculates an order total or accepts the one is sent.

## Login service (process, Application server)

| Category | Result |
| --- | --- |
| Spoofing | **Applies** — pretending to be someone else |
| Tampering | Checked, nothing found |
| Repudiation | Checked, nothing found |
| Information disclosure | Checked, nothing found |
| Denial of service | Checked, nothing found |
| Elevation of privilege | Checked, nothing found |

**What I found, and what I looked for and did not find:** I found that service accepted a five-character password at registration, and it takes on a security-question answer that the form says cannot be changed later. So, a permanent recovery secret can never be rotated. if someone guesses either one that will be enough to be treated as that customer and there is no remedy for the second one after it leaks. What I looked for and didn't find was, I made sure not to hammer the sign-in form, so I have no evidence weather entering multiple wrong passwords are throttled or will lock me out. I saw nothing showing whether a sign-in attempt is recorded anywhere, which is what would let anyone show later which sign-in was genuine. Nothing I did touched tampering, denial of service, or privilege on this element.

## Product database (data store, Data store)

| Category | Result |
| --- | --- |
| Spoofing | Checked, nothing found |
| Tampering | Checked, nothing found |
| Repudiation | Checked, nothing found |
| Information disclosure | Checked, nothing found |
| Denial of service | Checked, nothing found |
| Elevation of privilege | Checked, nothing found |

**What I found, and what I looked for and did not find:** I never observed a query, a connection, or a record being written, so I am recording all six categories as checked and unsupported. what I looked for and didn't find was the "apple" search. The "apple" search returning "Pineapple Juice", shows a server-side substring lookup exists and that text I typed reaches it in some form. This is the element I know least about, and it is the one my step 4 confidence note already flags as the weakest boundary

## Uploaded files (data store, Data store)

| Category | Result |
| --- | --- |
| Spoofing | Checked, nothing found |
| Tampering | Checked, nothing found |
| Repudiation | Checked, nothing found |
| Information disclosure | Checked, nothing found |
| Denial of service | Checked, nothing found |
| Elevation of privilege | Checked, nothing found |

**What I found, and what I looked for and did not find:** I notice a gap in my own model. The sample model listed this store with no arrow touching it all. I drew one inbound arrow because I saw the profile-picture form that would feed it, but I have no arrow showing a stored image being served back out to any browse. What I looked for and did not find: I never completed an upload and never located a stored file, so I do not know where the file lands, what name it is given, what types are accepted, or who can ask for it afterwards.

## Product reviews (data store, Data store)

| Category | Result |
| --- | --- |
| Spoofing | Checked, nothing found |
| Tampering | Checked, nothing found |
| Repudiation | Checked, nothing found |
| Information disclosure | Checked, nothing found |
| Denial of service | Checked, nothing found |
| Elevation of privilege | Checked, nothing found |

**What I found, and what I looked for and did not find:** I found nothing at this element directly, but I confirmed both halves of the mechanism exist — I saw the write form on a product page, and I saw another customer's review text displayed back to me on that same page. So, text one customer writes are stored here and later rendered in a different customer's browser. what I looked for and did not find, I never submitted a review, so I did not confirm whether the text escaped when it is rendered, whether the 160-character limit is enforced on the server, or whether a review can be written for a product the account never bought.

## External image host (external entity, Third party)

| Category | Result |
| --- | --- |
| Spoofing | Checked, nothing found |
| Tampering | Checked, nothing found |
| Repudiation | Checked, nothing found |
| Information disclosure | Checked, nothing found |
| Denial of service | Checked, nothing found |
| Elevation of privilege | Checked, nothing found |

**What I found, and what I looked for and did not find:** I found nothing at this element, and I want to be clear that I am not certain it belongs in the model. What I did observe is the control that puts it there: the profile page offers an Image URL field with a Link Image button beside the file upload, so a customer can hand the application an address instead of a file. what I looked for and did not find was I never watched the network while linking an image, so I do not know whether the fetch is made by the server or by my own browser — and that single observation decides whether this element and its boundary exist at all
