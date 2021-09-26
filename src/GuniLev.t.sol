// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./GuniLev.sol";

contract GuniLevTest is DSTest {

    VatLike public vat;
    bytes32 public ilk;
    GemJoinLike public join;
    DaiJoinLike public daiJoin;
    GUNITokenLike public guni;
    IERC20 public dai;
    IERC20 public otherToken;
    IERC3156FlashLender public lender;
    GUNIRouterLike public router;
    GuniLev public lev;

    function setUp() public {
        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        join = GemJoinLike(0xbFD445A97e7459b0eBb34cfbd3245750Dba4d7a4);
        daiJoin = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        guni = GUNITokenLike(join.gem());
        ilk = join.ilk();
        dai = IERC20(daiJoin.dai());
        otherToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;    // USDC
        lender = IERC3156FlashLender(0x1EB4CF3A948E7D72A198fe073cCb8C7a948cD853);
        router = GUNIRouterLike(0x8CA6fa325bc32f86a12cC4964Edf1f71655007A7);

        lev = new GuniLev(join, daiJoin, otherToken, lender, router);

        // Set the user up with some money
        giveTokens(address(dai), 50_000 * 1e18);
        vat.hope(address(lev));
        dai.approve(address(lev), type(uint256).max);
    }

    function giveTokens(address token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (ERC20Like(token).balanceOf(address(this)) == amount) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                token,
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                token,
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (ERC20Like(token).balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    token,
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function test_open_position() public {
        lev.wind(dai.balanceOf(address(this)), 10 * 1e4, 0);
    }

}
