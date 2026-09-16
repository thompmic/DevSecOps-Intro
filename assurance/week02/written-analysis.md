# Written analysis — Threat Model v1.0

CPS 5981 01, Week 02

**Fork:** https://github.com/thompmic/DevSecOps-Intro
**Commit:** 23d65195da19336866623dd5e5ed6e23e809327c
**Visibility:** Public
**Collaborators:** none
**Declared AI use:** Claude was used for wording and structure on the abuse cases, the written analysis and Analysis Memo 2. The system observations, the trust-boundary judgements, the mission statement and the mission effects are my own, from running the target in step 1.

## 1. Which of your abuse cases are supported by evidence you gathered, and which rest on reasoning about the design?

Cases 2 and 5 rest on two measured facts the five-character password and the unchangeable answer and on one assumption each. For case 2 I never tested whether repeated wrong attempts are throttled, so I cannot say how expensive guessing actually is. For case 5 I never exercised the recovery path, so that it accepts the answer as sufficient proof is inference from the fact that the form collects it. And Case 4 is half and half. The substring behavior is measured and is what makes walking the catalogue practical. The absence of rate limiting is not I never sent traffic at volume, so I have no evidence in either direction, and it would be wrong to present that as a finding.

## 2. What does STRIDE not surface for this target?

It asks what someone could do to an element, so it never asks what happens when nothing goes wrong. Cases 3 and 4 consist entirely of permitted actions. The employee reading order histories is doing their job with their own access; the script running searches is asking questions the shop is willing to answer. I could not tick a category for either, because no category is about an authorized action. Additionally, it has no place for whether damage can be undone. What separates case 5 from case 2 is permanence — the answer cannot be changed once it is known. Both cases would carry the same letter. The letters classify the act, not whether there is any way back.

## 3. Which trust boundary are you least confident about, and what would settle it?

Application server → Third party. I am less confident about this one than the other three, and the reason is different in kind: for the other three I at least observed both endpoints, so the question is how much passes and what is checked. Here I do not know whether the boundary exists at all. I saw the Image URL field and the Link Image button on the profile page, so I know the control is real but I never watched the network while using it, so I cannot say whether the request goes out from the application server or from my own browser. If it is my browser, then nothing leaves the server, the third-party zone I drew is wrong, and case 6 has no subject. What would settle it: open the browser's network view, put in a URL I control, press Link Image, and look at whether the request appears in the browser's own request list. If it does, the browser is fetching and the boundary is mine, not the shops. If nothing appears there but the image resolves, the server made the request and the boundary is real. One observation, about two minutes, and it decides an element, a zone, a boundary and an abuse case together.

## 4. If this system had twice as many users, which case moves up your list, and why?

I believe Case 3 moves furthest up, and it is not because it becomes more likely. The chance of any one employee looking up a customer nobody asked about does not change with user count. What changes is that each unjustified lookup now sits among twice as many legitimate ones, and the pool of people to look up has doubled. So it gets harder to notice and wider in reach at the same time, and I already found nothing showing a lookup is recorded anywhere. A case that is invisible at one scale and still invisible at twice the scale, with double the victims, is the one I would move to the top.
