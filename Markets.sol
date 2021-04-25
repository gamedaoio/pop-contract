pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: SimPL-2.0

// import "./interface/IERC20.sol";
// import "./interface/IERC721.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// import "./lib/UInteger.sol";
// import "./lib/Util.sol";

contract Markets {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    struct Order {
        uint256 id;
        address owner;
        address nft;
        uint256 nftId;
        address money;
        uint256 price;
        uint256 ordertime;
        address buyer;
        uint256 dealtime;
    }

    struct MoneyWhite {
        bool enabled;
        uint256 priceMin;
        uint256 feeRatio;
        uint256 amounts;
        uint256 counter;
    }

    event Trade(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        address nft,
        uint256 nftId,
        address money,
        uint256 price
    );

    uint256 public constant FEE_DENOMINATOR = 10000;
    address public feeAddr;

    uint256 public idCount = 0;
    mapping(address => Order[]) public orders;

    mapping(address => uint256) public userIdCount;

    mapping(address => mapping(uint256 => uint256)) public nftIndexes;

    mapping(address => mapping(uint256 => uint256)) public orderIndexes;

    mapping(address => bool) public nftWhites;
    mapping(address => bool) public proxyWhites;

    mapping(address => mapping(address => MoneyWhite)) public moneyWhites;

    mapping(address => mapping(address => uint256)) public balances;

    mapping(address => mapping(uint256 => Order[])) public nftOrders; //历史
    mapping(address => Order[]) public myPurchasedOrders;
    mapping(address => Order[]) public myNftSoldOrders;
    Order[] public lastOrders;

    address public governance;

    constructor(address _feeAddr) {
        governance = msg.sender;
        feeAddr = _feeAddr;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setNftWhite(address addr, bool enable) external CheckPermit() {
        nftWhites[addr] = enable;
    }

    modifier CheckPermit() {
        require(msg.sender == governance, "no permit");
        _;
    }

    function setProxyWhite(address addr, bool enable) external CheckPermit() {
        proxyWhites[addr] = enable;
    }

    function setMoneyWhite(
        address nft,
        address addr,
        bool enable,
        uint256 priceMin,
        uint256 feeRatio
    ) external CheckPermit() {
        MoneyWhite storage moneyWhite = moneyWhites[nft][addr];
        moneyWhite.enabled = enable;
        moneyWhite.priceMin = priceMin;
        moneyWhite.feeRatio = feeRatio;
        moneyWhite.amounts = 0;
        moneyWhite.counter = 0;
    }

    function ordersLength(address nft) external view returns (uint256) {
        return orders[nft].length;
    }

    function getOrders(
        uint256 startIndex,
        uint256 endIndex,
        uint256 resultLength,
        address owner,
        address nft,
        address money
    ) external view returns (Order[] memory) {
        if (endIndex == 0) {
            endIndex = orders[nft].length;
        }
        if (resultLength == 0) {
            resultLength = orders[nft].length;
        }

        require(startIndex <= endIndex, "invalid index");

        Order[] memory result = new Order[](resultLength);

        uint256 len = 0;
        for (
            uint256 i = startIndex;
            i != endIndex && len != resultLength;
            ++i
        ) {
            Order storage order = orders[nft][i];

            if (owner != address(0) && owner != order.owner) {
                continue;
            }

            if (nft != address(0) && nft != order.nft) {
                continue;
            }

            if (money != address(0) && money != order.money) {
                continue;
            }

            result[len++] = order;
        }

        return result;
    }

    function mySoldOrdersLength(address owner) external view returns (uint256) {
        return myNftSoldOrders[owner].length;
    }

    function getMySoldOrders(
        address owner,
        uint256 startIndex,
        uint256 endIndex,
        uint256 resultLength
    ) external view returns (Order[] memory) {
        if (endIndex == 0) {
            endIndex = myNftSoldOrders[owner].length;
        }
        if (resultLength == 0) {
            resultLength = myNftSoldOrders[owner].length;
        }

        require(startIndex <= endIndex, "invalid index");

        Order[] memory result = new Order[](resultLength);

        uint256 len = 0;
        for (
            uint256 i = startIndex;
            i != endIndex && len != resultLength;
            ++i
        ) {
            Order storage order = myNftSoldOrders[owner][i];
            result[len++] = order;
        }

        return result;
    }

    function myPurchasedOrdersLength(address owner)
        external
        view
        returns (uint256)
    {
        return myPurchasedOrders[owner].length;
    }

    function getMyPurchasedOrders(
        address owner,
        uint256 startIndex,
        uint256 endIndex,
        uint256 resultLength
    ) external view returns (Order[] memory) {
        if (endIndex == 0) {
            endIndex = myPurchasedOrders[owner].length;
        }
        if (resultLength == 0) {
            resultLength = myPurchasedOrders[owner].length;
        }

        require(startIndex <= endIndex, "invalid index");

        Order[] memory result = new Order[](resultLength);

        uint256 len = 0;
        for (
            uint256 i = startIndex;
            i != endIndex && len != resultLength;
            ++i
        ) {
            Order storage order = myPurchasedOrders[owner][i];
            result[len++] = order;
        }

        return result;
    }

    function getLastOrders() external view returns (Order[] memory) {
        Order[] memory result = new Order[](lastOrders.length);
        for (uint256 i = 0; i < lastOrders.length; i++) {
            result[i] = lastOrders[i];
        }

        return result;
    }

    function balanceOf(address user, address[] memory tokens)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory _balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            _balances[i] = balances[user][tokens[i]];
        }

        return _balances;
    }

    function sell(
        address nft,
        uint256 nftId,
        address token,
        uint256 price
    ) external {
        require(nftWhites[nft], "nft not in white list");
        address owner = msg.sender;

        //transferFrom
        IERC721(nft).transferFrom(owner, address(this), nftId);

        _addOrder(owner, nft, nftId, token, price);
    }

    function _addOrder(
        address owner,
        address nft,
        uint256 nftId,
        address money,
        uint256 price
    ) internal {
        MoneyWhite storage moneyWhite = moneyWhites[nft][money];
        require(moneyWhite.enabled, "money not in white list");
        require(price >= moneyWhite.priceMin, "money price too low");

        Order memory order =
            Order({
                id: ++idCount,
                owner: owner,
                nft: nft,
                nftId: nftId,
                money: money,
                price: price,
                ordertime: block.timestamp,
                buyer: address(0),
                dealtime: 0
            });

        // orderIndexes[nft][order.id] = orders[nft].length;
        nftIndexes[nft][nftId] = orders[nft].length;
        orders[nft].push(order);

        // myOrders.push(order);

        // emit Trade(order.id, address(0), owner, nft, nftId, money, price);
    }

    function cancelOrder(address nft, uint256 nftId) external {
        uint256 index = nftIndexes[nft][nftId];
        // uint256 index = orderIndexes[nft][id];
        Order memory order = orders[nft][index];
        require(order.nftId == nftId, "id not match");
        require(order.owner == msg.sender, "you not own the order");

        Order storage tail = orders[nft][orders[nft].length - 1];
        nftIndexes[nft][tail.nftId] = index;
        delete nftIndexes[nft][nftId];

        // orderIndexes[nft][tail.id] = index;
        // delete orderIndexes[nft][id];

        orders[nft][index] = tail;
        orders[nft].pop();

        // emit Trade(
        //     order.id,
        //     order.owner,
        //     address(0),
        //     order.nft,
        //     order.nftId,
        //     order.money,
        //     order.price
        // );

        IERC721(order.nft).transferFrom(
            address(this),
            order.owner,
            order.nftId
        );
    }

    function detail(address nft, uint256 nftId)
        external
        view
        returns (Order memory)
    {
        uint256 idx = nftIndexes[nft][nftId];
        return orders[nft][idx];
    }

    function history(address nft, uint256 nftId)
        external
        view
        returns (Order[] memory)
    {
        return nftOrders[nft][nftId];
    }

    function buy(address nft, uint256 nftId) external payable {
        uint256 idx = nftIndexes[nft][nftId];
        Order memory order = orders[nft][idx];
        if (order.money != address(~uint256(0))) {
            IERC20 money = IERC20(order.money);
            require(
                money.transferFrom(msg.sender, address(this), order.price),
                "transfer money failed"
            );
        }

        _buy(msg.sender, nft, nftId);
    }

    function buyProxy(
        address user,
        address nft,
        uint256 nftId
    ) external payable {
        require(proxyWhites[msg.sender], "proxy not in white list");

        uint256 idx = nftIndexes[nft][nftId];
        Order memory order = orders[nft][idx];
        if (order.money != address(~uint256(0))) {
            IERC20 money = IERC20(order.money);
            require(
                money.transferFrom(msg.sender, address(this), order.price),
                "transfer money failed"
            );
        }

        _buy(user, nft, nftId);
    }

    function _buy(
        address user,
        address nft,
        uint256 nftId
    ) internal {
        uint256 index = nftIndexes[nft][nftId];
        Order memory order = orders[nft][index];
        require(order.nftId == nftId, "id not match");

        Order storage tail = orders[nft][orders[nft].length - 1];

        nftIndexes[nft][tail.nftId] = index;
        delete nftIndexes[nft][nftId];

        orders[nft][index] = tail;
        orders[nft].pop();

        emit Trade(
            order.id,
            order.owner,
            user,
            order.nft,
            order.nftId,
            order.money,
            order.price
        );

        MoneyWhite storage moneyWhite = moneyWhites[nft][order.money];
        address payable feeAccount = payable(feeAddr);
        uint256 fee = order.price.mul(moneyWhite.feeRatio).div(FEE_DENOMINATOR);
        moneyWhite.amounts = moneyWhite.amounts.add(order.price);
        moneyWhite.counter++;

        if (order.money == address(~uint256(0))) {
            require(msg.value == order.price, "invalid money amount");
            feeAccount.transfer(fee);
        } else {
            IERC20 money = IERC20(order.money);

            require(money.transfer(feeAccount, fee), "transfer money failed");
        }

        balances[order.owner][order.money] += order.price.sub(fee);

        order.buyer = user;
        order.dealtime = block.timestamp;
        myPurchasedOrders[user].push(order);
        myNftSoldOrders[order.owner].push(order);
        nftOrders[order.nft][order.nftId].push(order);

        if (lastOrders.length > 100) {
            delete lastOrders[0];
        }
        lastOrders.push(order);

        IERC721(order.nft).transferFrom(address(this), user, order.nftId);
    }

    function withdraw(address money) external {
        address payable owner = msg.sender;

        uint256 balance = balances[owner][money];
        require(balance > 0, "no balance");
        balances[owner][money] = 0;

        if (money == address(~uint256(0))) {
            owner.transfer(balance);
        } else {
            require(
                IERC20(money).transfer(owner, balance),
                "transfer money failed"
            );
        }
    }
}
