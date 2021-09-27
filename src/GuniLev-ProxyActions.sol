// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

interface VatLike {
    function hope(address usr) external;
    function nope(address usr) external;
}

interface GuniLevLike {
    function wind(uint256, uint256) external;
}

// Extra safety when managing your vault
// Use with ds-proxy or similar
contract GuniLevProxyActions {

    VatLike public immutable vat;
    IERC20 public immutable dai;
    GuniLevLike public immutable lev;

    constructor(VatLike _vat, IERC20 _dai, GuniLevLike _lev) {
        vat = _vat;
        dai = _dai;
        lev = _lev;
    }

    function wind(uint256 principal, uint256 minExchangeBPS) external {
        vat.hope(address(lev));
        dai.approve(address(lev), principal);
        lev.wind(principal, minExchangeBPS);
        vat.nope(address(lev));     // Deny access after we are done just to be extra safe in case of contract exploit
    }

}
