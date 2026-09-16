# Trust boundaries

Threat Model v1.0 — CPS 5981 01, Week 02

Boundaries are derived from the zone each element sits in. A flow whose endpoints are in
different zones crosses one. Direction matters: the two directions between the same pair of
zones are separate boundaries, because the assumption being made differs.

Crossing flows: 11  —  distinct boundaries: 4

## 1. User's browser → Application server

**What crosses:** email address, password, and a permanent security-question answer; search terms; basket and order details; review text for a product; a profile picture file, or a URL for the server to fetch

**Why this is a real boundary:** When running for this lab and shop the login service assumed the email address, password and security-question answers were typed by the person they belong to. The shop is also assuming the search terms, basket contents, review text and image URL contain what each form asked for. The registration form also shows the far side accepting a password as short as five characters and a security-question answer marked "this cannot be changed later" — so it takes on a permanent recovery secret it can never rotate. 

**Confidence, and what would settle it:** I registered an account and watched exactly what the form collects. Less confident about what re-checking happens once it arrives. I never observed whether the server recalculates an order total rather than accepting the one it is sent, whether the 160-character review limit is enforced anywhere but the browser, or what file types the upload accept. Watching a single order request and a single upload would settle all three.

## 2. Application server → User's browser

**What crosses:** session token in a cookie; product listings and other customers' review text

**Why this is a real boundary:** The server releases two things into an environment it does not control: the token that later proves who the customer is, and text written by other customers. Also, the server is assuming the browser keeps the token away from whatever else runs on the page, and that text one customer wrote is safe to render in another customer's browser. Command 3 showed no Content-Security-Policy header is sent, so the page places no restriction on which scripts may run — while X-Content-Type-Options and X-Frame-Options are set, which makes this a specific omission rather than a server nobody configured

**Confidence, and what would settle it:** Confident about the missing header: I checked it by hand and read the full response. Confident that both halves of the review mechanism exist: I saw the write form on a product page and saw another customer's review displayed to me. Not confident about the cookie — I never read the Set-Cookie line, so I do not know whether the token is reachable from script. also, I never submitted anything into a review, so I do not know whether the text is escaped when it is rendered. Reading the Set-Cookie flags, and submitting one harmless marker into a review, would settle both

## 3. Application server → Data store

**What crosses:** product and order records; stored review text; stored profile images

**Why this is a real boundary:**  When searching "apple" returned "Pineapple Juice", so my search term reaches a server-side lookup doing substring matching — the term is carried into that lookup in some form. The data store trusts that anything the application asks for has already been authorized. It has no way to tell a query raised on behalf of a signed-in customer from one assembled out of text that customer typed. 

**Confidence, and what would settle it:**  I'm not confident, at least not like the others. I never observed a query, a connection, or a record being written. This rests on how applications of this kind are usually built rather than on anything I saw. Reading the data-access path, or watching a single order being written, would settle it.

## 4. Application server → Third party

**What crosses:** a request for the image URL the customer supplied

**Why this is a real boundary:** The far side is a host the customer chooses. The profile page offers an "Image URL" field with a Link Image button beside the file upload, so a customer can hand the application an address and have it fetched. The application is assuming that address points at an image, and at a host it is safe to contact — an assumption about a destination supplied by the same person whose input it is supposed to be checking.

**Confidence, and what would settle it:** I am confident that the control exists the field and the button are on the profile page when I went to upload the image. also, I do not know whether the fetch is made by the server or by my own browser and that difference decides whether this boundary exists at all. Watching the network while linking an image would settle it.
