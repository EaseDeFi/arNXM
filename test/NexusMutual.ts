// got from nexusmutual/smart-contracts and changed to typescript
import { ethers } from "hardhat";
import { Contract, ContractFactory, Signer, BigNumber } from "ethers";
import { time } from "@openzeppelin/test-helpers";
import { hex, hexSized } from './utils';
import { deployProxy, upgradeProxy, transferProxyOwnership } from "./OwnedUpgradeabilityProxy";

function ether(amount: string) : BigNumber {
  return ethers.utils.parseEther(amount);
}
const QE = '0x51042c4d8936a7764d18370a6a0762b860bb8e07';
const INITIAL_SUPPLY = ether('1500000');
const POOL_DAI = ether('900000');

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

  async deploy(dai: Contract, uniswapFactory: Contract) {

    const DSValue = await ethers.getContractFactory('NXMDSValueMock');
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
    const dsv = await DSValue.deploy(owner);

    // regular contracts
    const cd = await ClaimsData.deploy();
    const cl = await Claims.deploy();
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
    const cp = await ClaimProofs.deploy();

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

    await pc.initialize(mr.address);

    await gv.initialize(
      3 * 24 * 3600, // tokenHoldingTime
      14 * 24 * 3600, // maxDraftTime
      5, // maxVoteWeigthPer
      40, // maxFollowers
      75, // specialResolutionMajPerc
      24 * 3600, // actionWaitingTime
    );

    await ps['initialize(address,uint256,uint256,uint256,uint256)'](
      tc.address,
      ether('20'), // min stake
      ether('20'), // min unstake
      10, // max exposure
      90 * 24 * 3600, // unstake lock time
    );

    await pd.changeMasterAddress(master.address);
    await pd.updateUintParameters(hexSized('MCRMIN', 8), ether('7000')); // minimum capital in eth
    await pd.updateUintParameters(hexSized('MCRSHOCK', 8), 50); // mcr shock parameter
    await pd.updateUintParameters(hexSized('MCRCAPL', 8), 20); // capacityLimit 10: seemingly unused parameter

    await cd.changeMasterAddress(master.address);
    await cd.updateUintParameters(hexSized('CAMINVT', 8), 36); // min voting time 36h
    await cd.updateUintParameters(hexSized('CAMAXVT', 8), 72); // max voting time 72h
    await cd.updateUintParameters(hexSized('CADEPT', 8), 7); // claim deposit time 7 days
    await cd.updateUintParameters(hexSized('CAPAUSET', 8), 3); // claim assessment pause time 3 days

    await td.changeMasterAddress(master.address);
    await td.updateUintParameters(hexSized('RACOMM', 8), 50); // staker commission percentage 50%
    await td.updateUintParameters(hexSized('CABOOKT', 8), 6); // "book time" 6h
    await td.updateUintParameters(hexSized('CALOCKT', 8), 7); // ca lock 7 days
    await td.updateUintParameters(hexSized('MVLOCKT', 8), 2); // ca lock mv 2 days

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
    await p1.connect(this.deployer).sendEther({ value: POOL_ETHER.div(2) });
    await p2.connect(this.deployer).sendEther({ value: POOL_ETHER.div(2) });
    await dai.transfer(p2.address, POOL_DAI);

    // add mcr
    await mc.addMCRData(
      20000, // mcr% = 200.00%
      ether('50000'), // mcr = 5000 eth
      ether('100000'), // vFull = 90000 ETH + 2M DAI = 90000 ETH + 10000 ETH = 100000 ETH
      [hexSized('ETH', 4), hexSized('DAI', 4)],
      [100, 20000], // rates: 1.00 eth/eth, 200.00 dai/eth
      20190103,
    );

    await p2.saveIADetails(
      [hexSized('ETH',4), hexSized('DAI',4)],
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

  async registerUser(member: string) {
    const fee = ether('0.002');
    await this.memberRoles.connect(this.deployer).payJoiningFee(member, { value: fee });
    await this.memberRoles.connect(this.deployer).kycVerdict(member, true);
  }
}
