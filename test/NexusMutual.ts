// got from nexusmutual/smart-contracts and changed to typescript
import { ethers } from "hardhat";
import { Contract, ContractFactory, Signer } from "ethers";
import { ether, time } from "@openzeppelin/test-helpers";
import { hex } from './utils';

const QE = '0x51042c4d8936a7764d18370a6a0762b860bb8e07';
const INITIAL_SUPPLY = ether('1500000');
const EXCHANGE_TOKEN = ether('10000');
const EXCHANGE_ETHER = ether('10');
const POOL_ETHER = ether('3500');
const POOL_DAI = ether('900000');

async function deployProxy(contract: ContractFactory) : Promise<Contract> {
  const OwnedUpgradeabilityProxy = await ethers.getContractFactory('OwnedUpgradeabilityProxy');
  const implementation = await contract.deploy();
  const proxy = await OwnedUpgradeabilityProxy.deploy(implementation.address);
  return contract.attach(proxy.address);
};

async function upgradeProxy(proxyAddress: string, contract: ContractFactory) {
  const OwnedUpgradeabilityProxy = await ethers.getContractFactory('OwnedUpgradeabilityProxy');
  const implementation = await contract.deploy();
  const proxy = await OwnedUpgradeabilityProxy.attach(proxyAddress);
  await proxy.upgradeTo(implementation.address);
};

async function transferProxyOwnership(proxyAddress: string, deployOwner: string) {
  const OwnedUpgradeabilityProxy = await ethers.getContractFactory('OwnedUpgradeabilityProxy');
  const proxy = await OwnedUpgradeabilityProxy.attach(proxyAddress);
  await proxy.transferProxyOwnership(deployOwner);
};

export class NexusMutual {
  deployer: Signer;
  master: Contract;
  nxm: Contract;
  claims: Contract;
  claimsData: Contract;
  claimsReward: Contract;
  claimProofs: Contract;
  mcr: Contract;
  tokenData: Contract;
  tokenFunctions: Contract;
  tokenController: Contract;
  pool1: Contract;
  pool2: Contract;
  poolData: Contract;
  quotation: Contract;
  quotationData: Contract;
  governance: Contract;
  proposalCategory: Contract;
  memberRoles: Contract;
  pooledStaking: Contract;
  
  constructor(deployer: Signer) {
    this.deployer = deployer;
  }

  async deploy(dai: Contract, mkr: Contract, uniswapFactory: Contract) {

    const DSValue = await ethers.getContractFactory('NXMDSValue');
    // nexusmutual
    const NXMToken = await ethers.getContractFactory('NXMToken');
    const Claims = await ethers.getContractFactory('Claims');
    const ClaimsData = await ethers.getContractFactory('ClaimsData');
    const ClaimsReward = await ethers.getContractFactory('ClaimsReward');
    const MCR = await ethers.getContractFactory('MCR');
    const TokenData = await ethers.getContractFactory('TokenData');
    const TokenFunctions = await ethers.getContractFactory('TokenFunctions');
    const Pool1 = await ethers.getContractFactory('Pool1Mock');
    const Pool2 = await ethers.getContractFactory('Pool2');
    const PoolData = await ethers.getContractFactory('PoolData');
    const Quotation = await ethers.getContractFactory('Quotation');
    const QuotationData = await ethers.getContractFactory('QuotationData');
    const ClaimProofs = await ethers.getContractFactory('ClaimProofs');

    // temporary contracts used for initialization
    const DisposableNXMaster = await ethers.getContractFactory('DisposableNXMaster');
    const DisposableMemberRoles = await ethers.getContractFactory('DisposableMemberRoles');
    const DisposableTokenController = await ethers.getContractFactory('DisposableTokenController');
    const DisposableProposalCategory = await ethers.getContractFactory('DisposableProposalCategory');
    const DisposableGovernance = await ethers.getContractFactory('DisposableGovernance');
    const DisposablePooledStaking = await ethers.getContractFactory('DisposablePooledStaking');

    // target contracts
    const NXMaster = await ethers.getContractFactory('NXMaster');
    const MemberRoles = await ethers.getContractFactory('MemberRoles');
    const TokenController = await ethers.getContractFactory('TokenController');
    const ProposalCategory = await ethers.getContractFactory('ProposalCategory');
    const Governance = await ethers.getContractFactory('Governance');
    const PooledStaking = await ethers.getContractFactory('PooledStaking');
    
    const owner = await this.deployer.getAddress();

    // deploy external contracts
    //const dai = await ERC20Mock.deploy();
    const dsv = await DSValue.deploy(owner);
    //const factory = await ExchangeFactoryMock.deploy();
    //const exchange = await ExchangeMock.deploy(dai.address, factory.address);

    // initialize external contracts
    await dai.mint(ether('10000000'));
    //await factory.setFactory(dai.address, exchange.address);
    //await dai.transfer(exchange.address, EXCHANGE_TOKEN);
    //await exchange.recieveEther({ value: EXCHANGE_ETHER });

    // regular contracts
    const cl = await Claims.deploy();
    const cd = await ClaimsData.deploy();
    const cr = await ClaimsReward.deploy();

    const mc = await MCR.deploy();
    const p1 = await Pool1.deploy();
    const p2 = await Pool2.deploy(uniswapFactory.address);
    const pd = await PoolData.deploy(owner, dsv.address, dai.address);

    const tk = await NXMToken.deploy(owner, INITIAL_SUPPLY);
    const td = await TokenData.deploy(owner);
    const tf = await TokenFunctions.deploy();

    const qt = await Quotation.deploy();
    const qd = await QuotationData.deploy(QE, owner);

    // proxy contracts
    const master = await deployProxy(DisposableNXMaster);
    const mr = await deployProxy(DisposableMemberRoles);
    const tc = await deployProxy(DisposableTokenController);
    const ps = await deployProxy(DisposablePooledStaking);
    const pc = await deployProxy(DisposableProposalCategory);
    const gv = await deployProxy(DisposableGovernance);

    // non-upgradable contracts
    const cp = await ClaimProofs.deploy(master.address);

    const contractType = code => {

      const upgradable = ['CL', 'CR', 'MC', 'P1', 'P2', 'QT', 'TF'];
      const proxies = ['GV', 'MR', 'PC', 'PS', 'TC'];

      if (upgradable.includes(code)) {
        return 2;
      }

      if (proxies.includes(code)) {
        return 1;
      }

      return 0;
    };

    const codes = ['QD', 'TD', 'CD', 'PD', 'QT', 'TF', 'TC', 'CL', 'CR', 'P1', 'P2', 'MC', 'GV', 'PC', 'MR', 'PS'];
    const addresses = [qd, td, cd, pd, qt, tf, tc, cl, cr, p1, p2, mc, { address: owner }, pc, mr, ps].map(c => c.address);

    await master.initialize(
      owner,
      tk.address,
      28 * 24 * 3600, // emergency pause time 28 days
      codes.map(hex), // codes
      codes.map(contractType), // types
      addresses, // addresses
    );

    await tc.initialize(
      master.address,
      tk.address,
      ps.address,
      30 * 24 * 3600, // minCALockTime
    );

    await mr.initialize(
      owner,
      master.address,
      tc.address,
      [owner], // initial members
      [ether('10000')], // initial tokens
      [owner], // advisory board members
    );

    await pc.initialize(mr.address, { gas: 10e6 });

    await gv.initialize(
      3 * 24 * 3600, // tokenHoldingTime
      14 * 24 * 3600, // maxDraftTime
      5, // maxVoteWeigthPer
      40, // maxFollowers
      75, // specialResolutionMajPerc
      24 * 3600, // actionWaitingTime
    );

    await ps.initialize(
      tc.address,
      ether('20'), // min stake
      ether('20'), // min unstake
      10, // max exposure
      90 * 24 * 3600, // unstake lock time
    );

    await pd.changeMasterAddress(master.address);
    await pd.updateUintParameters(hex('MCRMIN'), ether('7000')); // minimum capital in eth
    await pd.updateUintParameters(hex('MCRSHOCK'), 50); // mcr shock parameter
    await pd.updateUintParameters(hex('MCRCAPL'), 20); // capacityLimit 10: seemingly unused parameter

    await cd.changeMasterAddress(master.address);
    await cd.updateUintParameters(hex('CAMINVT'), 36); // min voting time 36h
    await cd.updateUintParameters(hex('CAMAXVT'), 72); // max voting time 72h
    await cd.updateUintParameters(hex('CADEPT'), 7); // claim deposit time 7 days
    await cd.updateUintParameters(hex('CAPAUSET'), 3); // claim assessment pause time 3 days

    await td.changeMasterAddress(master.address);
    await td.updateUintParameters(hex('RACOMM'), 50); // staker commission percentage 50%
    await td.updateUintParameters(hex('CABOOKT'), 6); // "book time" 6h
    await td.updateUintParameters(hex('CALOCKT'), 7); // ca lock 7 days
    await td.updateUintParameters(hex('MVLOCKT'), 2); // ca lock mv 2 days

    await gv.changeMasterAddress(master.address);
    await master.switchGovernanceAddress(gv.address);

    // trigger changeDependentContractAddress() on all contracts
    await master.changeAllAddress();

    await upgradeProxy(mr.address, MemberRoles);
    await upgradeProxy(tc.address, TokenController);
    await upgradeProxy(ps.address, PooledStaking);
    await upgradeProxy(pc.address, ProposalCategory);
    await upgradeProxy(master.address, NXMaster);
    await upgradeProxy(gv.address, Governance);

    await transferProxyOwnership(mr.address, master.address);
    await transferProxyOwnership(tc.address, master.address);
    await transferProxyOwnership(ps.address, master.address);
    await transferProxyOwnership(pc.address, master.address);
    await transferProxyOwnership(gv.address, master.address);
    await transferProxyOwnership(master.address, gv.address);

    const POOL_ETHER = ether('90000');
    const POOL_DAI = ether('2000000');

    // fund pools
    await p1.sendEther({ from: owner, value: POOL_ETHER.divn(2) });
    await p2.sendEther({ from: owner, value: POOL_ETHER.divn(2) });
    await dai.transfer(p2.address, POOL_DAI);

    // add mcr
    await mc.addMCRData(
      20000, // mcr% = 200.00%
      ether('50000'), // mcr = 5000 eth
      ether('100000'), // vFull = 90000 ETH + 2M DAI = 90000 ETH + 10000 ETH = 100000 ETH
      [hex('ETH'), hex('DAI')],
      [100, 20000], // rates: 1.00 eth/eth, 200.00 dai/eth
      20190103,
    );

    await p2.saveIADetails(
      [hex('ETH'), hex('DAI')],
      [100, 20000],
      20190103,
      true,
    );

    this.master = master;
    this.nxm = tk;
    this.claims = cl;
    this.claimsData = cd;
    this.claimsReward = cr;
    this.mcr = mc;
    this.tokenData = td;
    this.tokenFunctions = tf;
    this.tokenController = tc;
    this.pool1 = p1;
    this.pool2 = p2;
    this.poolData = pd;
    this.quotation = qt;
    this.quotationData = qd;
    this.governance = gv;
    this.proposalCategory = pc;
    this.memberRoles = mr;
    this.pooledStaking = ps;
    this.claimProofs = cp;
  }
}
