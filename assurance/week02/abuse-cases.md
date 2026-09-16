# Abuse cases

Threat Model v1.0 — CPS 5981 01, Week 02

**Mission:** This system succeeds when a customer's order is theirs alone, and the shop can verify what happened on an account was done by the actual customer not by someone pretending to be the customer

Each case names an actor, what they can already do, what they do with it, what stops being
true for the mission, and what that costs.

## Case 1

- **Actor:** a signed-in customer with an ordinary account
- **Capability:** can type text into the review form on any product page, and can change fields in a request before it is sent — the only limit I saw on review length was in the browser
- **Action sequence:** submit review text that is script rather than prose into a page that sends no Content-Security-Policy, and wait for another customer to open it
- **Mission effect:** an order appears under a customer's name that they did not place, and the shop cannot tell it apart from orders the actual customer placed
- **Impact:** refunds the shop cannot recover, and no way to establish afterwards which orders on that account were genuine

Because a signed-in customer with an ordinary account can submit review text that is script rather than prose into a page that sends no Content-Security-Policy, and wait for another customer to open it, an order appears under a customer's name that they did not place, and the shop cannot tell it apart from orders the actual customer placed occurs, costing refunds the shop cannot recover, and no way to establish afterwards which orders on that account were genuine.

## Case 2

- **Actor:** someone with no account and no credential of any kind
- **Capability:** can reach the registration and sign-in forms without signing in, and can read the password rule the form actually enforces — it accepted five characters from me
- **Action sequence:** work through likely passwords against an email address they already know, or go at the security-question answer instead, which the form says cannot be changed later
- **Mission effect:** the account answers to someone who guessed the account password and everything done on it afterwards is treated by the shop as the customer's own doing
- **Impact:** orders the shop has to refund, no way to establish which actions on the account were genuine, and an account the customer can never fully make theirs again

Because someone with no account and no credential of any kind can work through likely passwords against an email address they already know, or go at the security-question answer instead, which the form says cannot be changed later, the account answers to someone who guessed the account password and everything done on it afterwards is treated by the shop as the customer's own doing occurs, costing orders the shop has to refund, no way to establish which actions on the account were genuine, and an account the customer can never fully make theirs again.

## Case 3

- **Actor:** an employee handling customer complaint, using exactly the access their role gives them
- **Capability:** has enough access to look up a customer's account and order history in order to answer a complaint — which is the job, not a misuse of it
- **Action sequence:** look up customers nobody asked about, one at a time, inside the normal flow of the work, each lookup indistinguishable from a legitimate one
- **Mission effect:** what a customer bought is read by someone with no reason to read it, and the shop cannot say afterwards whose account was looked at or why
- **Impact:** customers' purchase histories in hands that had no reason to hold them, and no record that would let the shop answer a customer who asks who has seen their orders

Because an employee handling customer complaint, using exactly the access their role gives them can look up customers nobody asked about, one at a time, inside the normal flow of the work, each lookup indistinguishable from a legitimate one, what a customer bought is read by someone with no reason to read it, and the shop cannot say afterwards whose account was looked at or why occurs, costing customers' purchase histories in hands that had no reason to hold them, and no record that would let the shop answer a customer who asks who has seen their orders.

## Case 4

- **Actor:** a script with no browser, running unattended
- **Capability:** can issue requests at whatever rate it chooses and needs no account to run a search; I found no evidence of rate limiting, and I also did not test for it
- **Action sequence:** walk the search across short substrings to pull back the whole catalogue — searching "apple" returned "Pineapple Juice", so the lookup matches on substrings — or submit registrations and reviews at a volume no person would reach
- **Mission effect:** the shop's records stop describing what real customers did — accounts exist that belong to nobody and reviews exist that no person wrote, and the shop cannot separate them from the genuine ones
- **Impact:** a customer list and a set of reviews the shop cannot rely on, and decisions made on numbers that were never real customers

Because a script with no browser, running unattended can walk the search across short substrings to pull back the whole catalogue — searching "apple" returned "Pineapple Juice", so the lookup matches on substrings — or submit registrations and reviews at a volume no person would reach, the shop's records stop describing what real customers did — accounts exist that belong to nobody and reviews exist that no person wrote, and the shop cannot separate them from the genuine ones occurs, costing a customer list and a set of reviews the shop cannot rely on, and decisions made on numbers that were never real customers.

## Case 5

- **Actor:** an outsider who knows a particular customer's security-question answer from somewhere else — an old leak, a social media post, or simply knowing the person
- **Capability:** needs no password and no access to the customer's email, and holds an answer to something the form treats as proof of identity
- **Action sequence:** use the recovery path against that customer's account — and because the form states the answer cannot be changed later, the customer cannot invalidate it even after learning it is known
- **Mission effect:** a customer loses their account to someone who never had to guess anything, and there is no step the customer can take that makes it theirs alone again
- **Impact:** an account the shop can never restore to its customer, and a recovery route the shop cannot tell a genuine use of from a false one

Because an outsider who knows a particular customer's security-question answer from somewhere else — an old leak, a social media post, or simply knowing the person can use the recovery path against that customer's account — and because the form states the answer cannot be changed later, the customer cannot invalidate it even after learning it is known, a customer loses their account to someone who never had to guess anything, and there is no step the customer can take that makes it theirs alone again occurs, costing an account the shop can never restore to its customer, and a recovery route the shop cannot tell a genuine use of from a false one.

## Case 6

- **Actor:** a signed-in customer with an ordinary account
- **Capability:** has an Image URL field with a Link Image button on the profile page, beside the file upload, so they can hand the application an address instead of a file
- **Action sequence:** put in an address that is not an image host and not anywhere the application was meant to reach, and press the button — the destination is chosen by the same person whose input the application is supposed to be checking
- **Mission effect:** if the shop's own server is what fetches that address, then the shop is reaching destinations a customer picked while acting under its own name, and it cannot show afterwards which of those requests it ever intended to make
- **Impact:** requests made in the shop's name that it never chose, and no record that would let it show which ones were its own

Because a signed-in customer with an ordinary account can put in an address that is not an image host and not anywhere the application was meant to reach, and press the button — the destination is chosen by the same person whose input the application is supposed to be checking, if the shop's own server is what fetches that address, then the shop is reaching destinations a customer picked while acting under its own name, and it cannot show afterwards which of those requests it ever intended to make occurs, costing requests made in the shop's name that it never chose, and no record that would let it show which ones were its own.
