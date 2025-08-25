// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./TokenFarmV2.sol";
import "./DappToken.sol";
import "./LPToken.sol";

contract TokenFarmFactory {
    address public master; // dirección del TokenFarmV2 maestro
    TokenFarmV2[] public farms;

    event FarmCreated(address indexed farm, address lpToken, address owner);

    constructor(address _master) {
        master = _master;
    }

    function createFarm(
        LPToken _lpToken,
        DAppToken _dappToken,
        uint256 _initialReward,
        uint256 _minReward,
        uint256 _maxReward,
        uint256 _claimFee
    ) external returns (address) {
        address clone = Clones.clone(master);
        TokenFarmV2(clone).initialize(_dappToken, _lpToken, _initialReward, _minReward, _maxReward, _claimFee);
        farms.push(TokenFarmV2(clone));
        emit FarmCreated(clone, address(_lpToken), msg.sender);
        return clone;
    }
}
