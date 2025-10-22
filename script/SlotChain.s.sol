// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {Script} from 'forge-std/Script.sol';
import {SlotChain} from '../src/SlotChain.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import 'forge-std/console.sol';

contract DeploySlotChainImp is Script {
    address baseTokenAddress = vm.envAddress('SEPOLIA_USDT');
    address platformOwner = vm.envAddress('PLATFORM_OWNER');

    function run() external {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY_DEPLOYER');
        vm.startBroadcast(deployerPrivateKey);

        SlotChain slotchainDeployer = new SlotChain();

        bytes memory slotChainParams = abi.encodeWithSelector(
            SlotChain.initialize.selector,
            platformOwner,
            baseTokenAddress,
            platformOwner
        );

        ERC1967Proxy slotChainProxy = new ERC1967Proxy(
            address(slotchainDeployer),
            slotChainParams
        );

        console.log('SlotChain deployed at:', address(slotchainDeployer));
        console.log('DataRequestProxy deployed at:', address(slotChainProxy));
        vm.stopBroadcast();
    }
}
