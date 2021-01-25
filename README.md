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

## Testing

1. `git clone https://github.com/ArmorFi/arNXM.git`
2. `npm install --save-dev`
3. `npx hardhat test`

## Contracts

arNXMVault Master:      0x7eFf1f18644b84A391788923d53400e8fe455687<br>
ReferralRewards Master: 0xefF1CDc3CC01afAB104b00a7D9cd09619B94ae8F<br>
arNXMVault Proxy:       0x1337DEF1FC06783D4b03CB8C1Bf3EBf7D0593FC4<br>
ReferralRewards Proxy:  0x1337DEF1C79053dA23921a3634aDbD12f3b748A5<br>
arNXM token:            0x1337DEF18C680aF1f9f45cBcab6309562975b1dD<br>
arNFT token:            0x1337DEF1e9c7645352D93baf0b789D04562b4185<br>
Old arNFT token:        0x57318daf32e1f208fb84af5413c4185b8f66104d<br>
Multisig Admin:         0x1f28eD9D4792a567DaD779235c2b766Ab84D8E33<br>
Timelock Owned:         0x1337DEF11D788e62A253feA846A505EE1b57623f<br>
Armor token:            0x1337DEF16F9B486fAEd0293eb623Dc8395dFE46a<br>
FarmController:         0x1337DEF159da6F97dB7c4D0E257dc689837b9E70<br>
FarmController Master:  0x0Bdb7976c34aB05E5a9031F258B8956f68ee29cf<br>

arNXM:ETH Uni:      0x24ae7bdf4a9dee4d409503ffcfd5bc694e2c8a12<br>
arNXM:ETH Sushi:    0xcd1f8cda8be6a8c306a5b0ee759bad46a6f60cad<br>
arNXM:ETH 1inch:    0x07aFD11985bFcAA8016eEb9b00534c0B3A70CCaC<br>
arNXM:ETH Bal:      0x008F3DDE2Ed44BdC72800108d8309D16d55d6dD5<br>
ARMOR:ETH Uni:      0xf991f1e1b8acd657661c89b5cd452d86de76a8c1<br>
ARMOR:DAI Uni:      0xa659e66E116D354e779D8dbb35319AF67171ffb4<br>
ARMOR:WBTC Uni:     0x01Acad2228F18598CD2b8611aCD37992BF27313C<br>
ARMOR:ETH Sushi:    0x1b39d7f818aaf0318f6d0a66cd388c20c15fea94<br>
ARMOR:DAI Sushi:    0x4529AAA39DE655c8B4715DEa8b1dACEbbA255C74<br>
ARMOR:WBTC Sushi:   0x88aACE19997656F4eB1b8D3729226A4F97Ca6b2c<br>
ARMOR:ETH 1inch:    0xfDF5709D44b26A7DD112556Dd1B1cE53c0eAF454<br>
ARMOR:DAI 1inch:    0xD7b8Ef47C08F824ceA3d837afA61484e81d14BfB<br>
ARMOR:WBTC 1inch:   0x8C7442Bd71A1464f50efb216407B59584a2bcfF5<br>
ARMOR:DAI Bal:      0x148ac62a238a71D7fb8A5bA093B8BADF4DCc7DCC<br>
