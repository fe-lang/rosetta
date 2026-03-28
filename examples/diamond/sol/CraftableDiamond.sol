// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Craftable NFT Diamond — EIP-2535 style faceted contract for queue-based
/// crafting with ERC1155-style multi-token balances.
///
/// This is the Solidity counterpart to the Fe version. In a real Diamond
/// deployment, each facet section below would be a separate contract behind
/// a proxy with delegatecall routing. Here we inline everything for a clean
/// side-by-side comparison.
///
/// Architecture (4 logical facets, 1 contract for comparison):
///   CraftFacet   — queue a craft, claim after delay, cancel pending
///   TokenFacet   — ERC1155-style balanceOf, transfer
///   AdminFacet   — add/edit item types, set craft fee, pause
///   OwnerFacet   — ownership transfer (two-step)
contract CraftableDiamond {

    // -----------------------------------------------------------------------
    // Item type storage
    // -----------------------------------------------------------------------
    struct ItemType {
        uint256 cost;
        uint256 craftTime;
        uint256 maxSupply;
        uint256 minted;
    }

    ItemType[] public itemTypes;

    // -----------------------------------------------------------------------
    // Craft queue storage
    // -----------------------------------------------------------------------
    struct CraftEntry {
        address owner;
        uint256 itemTypeId;
        uint256 readyAt;
        bool claimed;
    }

    CraftEntry[] public craftQueue;
    uint256 public craftFee;

    // -----------------------------------------------------------------------
    // Token storage (ERC1155-style)
    // -----------------------------------------------------------------------
    // balances[owner][tokenId] => amount
    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    // -----------------------------------------------------------------------
    // Ownership storage
    // -----------------------------------------------------------------------
    address public owner;
    address public pendingOwner;
    bool public paused;

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------
    constructor(address _owner) {
        owner = _owner;
        paused = false;
        craftFee = 0;
    }

    // =======================================================================
    // Admin facet
    // =======================================================================

    /// Register a new item type. Returns the item_type_id.
    function addItemType(
        uint256 cost,
        uint256 craftTime,
        uint256 maxSupply
    ) external onlyOwner returns (uint256) {
        uint256 id = itemTypes.length;
        itemTypes.push(ItemType({
            cost: cost,
            craftTime: craftTime,
            maxSupply: maxSupply,
            minted: 0
        }));
        return id;
    }

    function setCraftFee(uint256 fee) external onlyOwner {
        craftFee = fee;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function isPaused() external view returns (bool) {
        return paused;
    }

    function getItemTypeCost(uint256 itemTypeId) external view returns (uint256) {
        return itemTypes[itemTypeId].cost;
    }

    function getItemTypeCraftTime(uint256 itemTypeId) external view returns (uint256) {
        return itemTypes[itemTypeId].craftTime;
    }

    function getItemTypeMaxSupply(uint256 itemTypeId) external view returns (uint256) {
        return itemTypes[itemTypeId].maxSupply;
    }

    function getItemTypeCount() external view returns (uint256) {
        return itemTypes.length;
    }

    // =======================================================================
    // Craft facet
    // =======================================================================

    /// Queue a craft for the given item type. Returns the queue ID.
    /// Burns currency tokens (token_id 0) equal to item cost + craft fee.
    function craft(uint256 itemTypeId) external whenNotPaused returns (uint256) {
        require(itemTypeId < itemTypes.length, "invalid item type");

        ItemType storage it = itemTypes[itemTypeId];
        uint256 totalCost = it.cost + craftFee;

        // Burn currency tokens (token 0) from caller
        if (totalCost > 0) {
            uint256 bal = balanceOf[msg.sender][0];
            require(bal >= totalCost, "insufficient currency");
            balanceOf[msg.sender][0] = bal - totalCost;
        }

        // Create queue entry
        uint256 queueId = craftQueue.length;
        craftQueue.push(CraftEntry({
            owner: msg.sender,
            itemTypeId: itemTypeId,
            readyAt: block.number + it.craftTime,
            claimed: false
        }));

        return queueId;
    }

    /// Claim a completed craft. Mints the item NFT to the queue owner.
    function claim(uint256 queueId) external whenNotPaused returns (bool) {
        CraftEntry storage entry = craftQueue[queueId];
        require(!entry.claimed, "already claimed");
        require(entry.owner != address(0), "invalid entry");

        // Check craft time elapsed
        if (block.number < entry.readyAt) return false;

        // Check max supply
        ItemType storage it = itemTypes[entry.itemTypeId];
        if (it.maxSupply > 0) {
            require(it.minted < it.maxSupply, "max supply reached");
        }

        // Mark claimed
        entry.claimed = true;

        // Mint: token_id = itemTypeId + 1 (0 is reserved for currency)
        uint256 tokenId = entry.itemTypeId + 1;
        balanceOf[entry.owner][tokenId] += 1;
        it.minted += 1;

        return true;
    }

    /// Cancel a pending craft (only by queue owner, only if not yet claimed).
    function cancelCraft(uint256 queueId) external returns (bool) {
        CraftEntry storage entry = craftQueue[queueId];
        require(entry.owner == msg.sender, "not queue owner");
        require(!entry.claimed, "already claimed");

        // Mark as claimed so it can't be used again
        entry.claimed = true;
        // No refund — burned currency stays burned.
        return true;
    }

    function getCraftReady(uint256 queueId) external view returns (uint256) {
        return craftQueue[queueId].readyAt;
    }

    function getCraftOwner(uint256 queueId) external view returns (uint256) {
        return uint256(uint160(craftQueue[queueId].owner));
    }

    // =======================================================================
    // Token facet (ERC1155 subset)
    // =======================================================================

    function transfer(
        address to,
        uint256 tokenId,
        uint256 amount
    ) external whenNotPaused returns (bool) {
        uint256 bal = balanceOf[msg.sender][tokenId];
        if (bal < amount) return false;
        balanceOf[msg.sender][tokenId] = bal - amount;
        balanceOf[to][tokenId] += amount;
        return true;
    }

    function totalMinted(uint256 itemTypeId) external view returns (uint256) {
        return itemTypes[itemTypeId].minted;
    }

    // =======================================================================
    // Owner facet — two-step ownership transfer
    // =======================================================================

    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);
    }
}
