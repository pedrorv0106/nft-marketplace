const { expect, use } = require("chai");
const { BigNumber } = require("ethers");

describe("WethReceiver contract", function () {
  const name = "Dbilia Token";
  const symbol = "DBT";
  const feePercent = 25; // 2.5%
  let DbiliaToken;
  let WethReceiver;
  let WethTest;
  const wethInitialSupply = BigNumber.from(1000000).mul(
    BigNumber.from((1e18).toString())
  );
  let ceo;
  let dbilia;
  let beneficiary;
  let user;
  let user2;
  let addrs;

  const realPasscode = "protected";
  const passcode = ethers.utils.hexZeroPad(
    ethers.utils.formatBytes32String(realPasscode),
    32
  );

  beforeEach(async function () {
    DbiliaToken = await ethers.getContractFactory("DbiliaToken");
    WethTest = await ethers.getContractFactory("WethTest");
    WethReceiver = await ethers.getContractFactory("WethReceiver");

    [ceo, dbilia, beneficiary, user, user2, ...addrs] =
      await ethers.getSigners();

    WethTest = await WethTest.deploy(wethInitialSupply);
    DbiliaToken = await DbiliaToken.deploy(name, symbol, feePercent, WethTest.address, beneficiary.address);
    WethReceiver = await WethReceiver.deploy(
      DbiliaToken.address,
      WethTest.address,
      beneficiary.address
    );
  });

  beforeEach(async function () {
    // await DbiliaToken.changeDbiliaTrust(dbilia.address);
  });

  describe("Deployment", function () {
    it("Should set the right beneficiary", async function () {
      expect(await WethReceiver.beneficiary()).to.equal(beneficiary.address);
    });
    it("Should set the right weth", async function () {
      expect(await WethReceiver.weth()).to.equal(WethTest.address);
    });
  });

  describe("Receive WETH", function () {
    const productId = "60ad481e27a4265b10d73b13";
    const amount = BigNumber.from(0.001 * 1e18);

    it("Beneficiary should receive the transferred amount", async function () {
      const beneficiaryBalanceBefore = await WethTest.balanceOf(
        beneficiary.address
      );

      await WethTest.connect(ceo).transfer(user.address, amount);

      await WethTest.connect(user).approve(WethReceiver.address, amount);

      expect(await WethReceiver.connect(user).receiveWeth(productId, amount))
        .to.emit(WethReceiver, "ReceiveWeth")
        .withArgs(user.address, productId, amount);

      const beneficiaryBalanceAfter = await WethTest.balanceOf(
        beneficiary.address
      );

      expect(beneficiaryBalanceAfter - beneficiaryBalanceBefore).to.equal(
        amount
      );
    });

    it("Invalid product ID or invalid amount should revert", async function () {
      await WethTest.connect(ceo).transfer(user.address, amount);

      await WethTest.connect(user).approve(WethReceiver.address, amount);

      await expect(
        WethReceiver.connect(user).receiveWeth("", amount)
      ).to.be.revertedWith("WethReceiver: Invalid product Id");

      await expect(
        WethReceiver.connect(user).receiveWeth(productId, 0)
      ).to.be.revertedWith("WethReceiver: Invalid amount");
    });
  });

  describe("Set beneficiary", function () {
    it("Only authorized account can set the beneficiary", async function () {
      await WethReceiver.connect(ceo).setBeneficiary(user.address);

      expect(await WethReceiver.beneficiary()).to.equal(user.address);
    });

    it("Unauthorized account setting the beneficiary should revert", async function () {
      await expect(
        WethReceiver.connect(user).setBeneficiary(user2.address)
      ).to.be.revertedWith("caller is not one of dbilia accounts");
    });
  });

  describe("SendPayout WETH", function () {
    const productId = "60ad481e27a4265b10d73b13";
    const amount = BigNumber.from(0.001 * 1e18);

    it("Beneficiary should receive the transferred amount", async function () {
      await WethTest.connect(ceo).transfer(user.address, amount);
      await WethTest.connect(user).approve(WethReceiver.address, amount);

      expect(await WethReceiver.connect(user).receiveWeth(productId, amount))
        .to.emit(WethReceiver, "ReceiveWeth")
        .withArgs(user.address, productId, amount);

      const beneficiaryBalanceBefore = await WethTest.balanceOf(
        beneficiary.address
      );

      await WethTest.connect(beneficiary).approve(WethReceiver.address, amount);

      await WethReceiver.connect(ceo).sendPayout(amount, user2.address);

      const beneficiaryBalanceAfter = await WethTest.balanceOf(
        beneficiary.address
      );

      expect(beneficiaryBalanceBefore - beneficiaryBalanceAfter).to.equal(
        amount
      );
    });

    it("Invalid amount should revert", async function () {
      await expect(
        WethReceiver.connect(ceo).sendPayout(0, WethReceiver.address)
      ).to.be.revertedWith("WethReceiver: Invalid amount");
    });

    it("Unauthorized account setting the sendPayout should revert", async function () {
      await expect(
        WethReceiver.connect(user).sendPayout(amount, user2.address)
      ).to.be.revertedWith("caller is not one of dbilia accounts");
    });
  });
});
