# arNXM

Armor's arNXM vault allows users to stake wNXM tokens with Nexus Mutual without the need to lock their tokens for 90 days. It's been created to boost the amount of capital being staked in the Nexus Mutual protocol.
<br>
<br>
The arNXM Vault accepts deposits of wNXM, exchanges them for arNXM at the current value (based on the amount of NXM the contract has and total supply of arNXM), then a user may withdraw to gain rewards from their staking.
<br>
<br>
Each week the "restake" function is called to withdraw any available funds and rewards from Nexus Mutual, it saves 10% of all assets under management for user withdrawals during the next week, stakes the remaining balance there may be, then unstakes 7% of all currently staked (the unstaking process takes 90 days so each week we do it in advance).
<br>
<br>
The arNXM Vault also includes referrals. Our frontend records affiliates who link users to the site, then submits their address when a user originally deposits. If the address submitted is 0, our beneficiary is counted as referrer. A user can submit themselves as their own referrer, but there's no decentralized way to prevent that. Referrers are then given, to start, 5% of all rewards the vault is given. These rewards are sent to an SNX-like contract which distributes them to referrers based on the % of arNXM users they have referred own. Referral rewards are split this way, as opposed to being taken individually, because there is no good way to do that without taking directly from a user balance as profits are contract-wide rather than individual.
<br>
<br>
If a claim is successful on Nexus mutual, the arNXM Vault is able to be paused for 7 days. This is because there is a known risk (that we are working on alleviating with further development on the Armor ecosystem) where, when a hack happens, users can immediately withdraw their funds from the vault without losing any wNXM that Nexus Mutual may take from the vault to repay insured users. This amount of loss is limited to what is kept in reserve and absorbed by users who are not fast enough to withdraw current reserve funds after a hack. The pause function is an attempt to further limit the amount that can be lost by users who do not manage to withdraw by disallowing withdrawals once a claim is made, although this will still be a bit of time after the hack happens so the initial run will still happen.