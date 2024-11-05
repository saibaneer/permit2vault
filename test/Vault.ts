import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { NewToken } from "../typechain-types";
import { Permit2Vault } from "../typechain-types/Vault.sol";
import { PermitTransferFrom, SignatureTransfer } from "@uniswap/permit2-sdk";

let testToken: NewToken;
let vaultContract: Permit2Vault;
const PERMIT_2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

describe("Vault", function () {

  before(async function () {
    this.timeout(400000);
    const [owner] = await hre.ethers.getSigners();

    const Token = await hre.ethers.getContractFactory("NewToken");
    testToken = await Token.deploy();
    await testToken.waitForDeployment();

    console.log("New Token is at: ", testToken.target);

    const Vault = await hre.ethers.getContractFactory("Permit2Vault");
    vaultContract = await Vault.deploy(PERMIT_2_ADDRESS);

    await vaultContract.waitForDeployment();

    console.log("Vault contract is at: ", vaultContract.target);

    console.log("Approving PERMIT2");
    const tx = await testToken.connect(owner).approve(PERMIT_2_ADDRESS, hre.ethers.MaxUint256);
    await tx.wait();

    console.log("Permit has permission!");
  });

  it("should allow me deposit into vault", async function () {
    this.timeout(400000);
    const [owner] = await hre.ethers.getSigners();
    const NONCE = "9";
    const deadline = (Math.floor(Date.now() / 1000) + 86400).toString();
    const chainId = 11155111;

    const permitSingle: PermitTransferFrom = {
      permitted: {
        token: testToken.target as string,
        amount: hre.ethers.parseEther("200").toString(),
      },
      spender: vaultContract.target as string,
      nonce: NONCE,
      deadline,
    };

    console.log("NONCE:", NONCE, "Deadline:", deadline);

    // Get permit signature data from SDK
    const { domain, types, values } =  SignatureTransfer.getPermitData(
      permitSingle,
      PERMIT_2_ADDRESS,
      chainId
    );

    console.log("Domain:", domain, "Types:", types, "Values:", values, "Domain version:", domain.version);

    const transferDetails = {
      spender: vaultContract.target as string,
      requestedAmount: hre.ethers.parseEther("200").toString(),
    };

    // Verify transfer details match permit
    expect(transferDetails.spender).to.equal(permitSingle.spender);
    expect(transferDetails.requestedAmount).to.equal(
      permitSingle.permitted.amount
    );

    const domainV6 = {
      name: domain.name,
      version: domain.version,
      chainId: chainId,
      verifyingContract: domain.verifyingContract,
    };
    // Sign and verify the permit

    const signature = await owner.signTypedData(domainV6, types, values);
    console.log("\nSignature Verification:");
    const recoveredAddress = ethers.verifyTypedData(
      domainV6,
      types,
      values,
      signature
    );
    console.log("Recovered address: ", recoveredAddress);
    expect(recoveredAddress).to.equal(owner.address);

    // Record initial balances
    const initialOwnerBalance = await testToken.balanceOf(owner.address);
    const initialVaultBalance = await testToken.balanceOf(vaultContract.target);
    const initialVaultOwnerBalance = await vaultContract.tokenBalancesByUser(
      
      owner.address,
      testToken.target,
    );

        const allowance = await testToken.allowance(owner.address, PERMIT_2_ADDRESS);
    console.log("Allowance:", allowance.toString());
    expect(allowance).to.be.greaterThan(hre.ethers.parseEther("200").toString(), "Insufficient allowance");

    const tx = await vaultContract
      .connect(owner)
      .depositERC20(
        testToken.target,
        hre.ethers.parseEther("200").toString(),
        NONCE,
        deadline,
        signature
      );
    await tx.wait(2);

    // Verify final state
    expect(await testToken.balanceOf(owner.address)).to.be.lessThan(
      initialOwnerBalance
    );
    expect(await testToken.balanceOf(vaultContract.target)).to.be.greaterThan(
      initialVaultBalance
    );
    expect(
      await vaultContract.tokenBalancesByUser(owner.address,testToken.target)
    ).to.equal(hre.ethers.parseEther("200"));
  });
  it("should allow me quiz the vault", async function(){
    const [owner] = await hre.ethers.getSigners();
    const balance = await testToken.balanceOf(vaultContract.target);
    console.log("Balance of vault:", balance);

    const vaultBalance = await vaultContract.tokenBalancesByUser(owner.address,testToken.target);
    console.log("Balance of user:", vaultBalance);
  })
});
