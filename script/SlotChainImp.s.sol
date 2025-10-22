// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {Script} from 'forge-std/Script.sol';
import {SlotChain} from '../src/SlotChain.sol';
import 'forge-std/console.sol';

contract DeploySlotChainIMP is Script {
    address platformOwner = vm.envAddress('PLATFORM_OWNER');

    function run() external {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY_DEPLOYER');
        vm.startBroadcast(deployerPrivateKey);

        SlotChain slotchainDeployer = new SlotChain();

        console.log('SlotChain deployed at:', address(slotchainDeployer));
        vm.stopBroadcast();
    }
}
