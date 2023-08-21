let AnkrStaking = artifacts.require("AnkrStakingPoly");

module.exports = function (deployer) {
  // deployment steps
  let underlying = "0x0E9b89007eEE9c958c0EDA24eF70723C2C93dD58";
  let rewardToken = "0x5662ac531A2737C3dB8901E982B43327a2fDe2ae";
  let stakingContract = "0x62a509ba95c75cabc7190469025e5abee4eddb2a";
  let treasuryAddress = "0x9784Ca49e40da05Ea7220EDE6FA235CF90eD53A4";
  let rewardRate = 100; // Reward per second
  deployer.deploy(
    AnkrStaking,
    underlying,
    rewardToken,
    stakingContract,
    treasuryAddress,
    rewardRate
  );
};
