// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Simplified Aavegotchi Tile Diamond — self-contained Solidity version.
///
/// Includes the Diamond proxy infrastructure (EIP-2535) so the reader
/// can see the overhead: selector mapping, delegatecall fallback,
/// diamondCut mutation, storage namespace discipline.
///
/// The business logic (TileFacet, ERC1155Facet) is functionally
/// equivalent to the Fe version in ../fe/src/lib.fe.
///
/// Dropped from the original: ERC998 parent-child tracking,
/// cross-diamond calls (onlyRealmDiamond), meta-transactions,
/// marketplace hooks, GLMR burn for craft-time reduction.

// ============================================================
//  Diamond infrastructure — this is what Fe eliminates
// ============================================================

interface IDiamondCut {
    enum FacetCutAction { Add, Replace, Remove }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    function diamondCut(
        FacetCut[] calldata _cut,
        address _init,
        bytes calldata _calldata
    ) external;
}

library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION =
        keccak256("diamond.standard.diamond.storage");

    struct FacetAddressAndPosition {
        address facetAddress;
        uint96 functionSelectorPosition;
    }

    struct DiamondStorage {
        mapping(bytes4 => FacetAddressAndPosition) selectorToFacet;
        bytes4[] selectors;
        mapping(bytes4 => bool) supportedInterfaces;
        address contractOwner;
    }

    function diamondStorage()
        internal
        pure
        returns (DiamondStorage storage ds)
    {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly { ds.slot := position }
    }

    function enforceIsContractOwner() internal view {
        require(
            msg.sender == diamondStorage().contractOwner,
            "LibDiamond: not owner"
        );
    }

    function setContractOwner(address _owner) internal {
        diamondStorage().contractOwner = _owner;
    }

    /// Adds selectors to the diamond. Only Add action shown for brevity;
    /// the real implementation also handles Replace and Remove.
    function diamondCut(
        IDiamondCut.FacetCut[] memory _cuts,
        address,
        bytes memory
    ) internal {
        DiamondStorage storage ds = diamondStorage();
        for (uint256 i; i < _cuts.length; i++) {
            IDiamondCut.FacetCut memory cut = _cuts[i];
            require(
                cut.action == IDiamondCut.FacetCutAction.Add,
                "LibDiamond: only Add supported in this simplified version"
            );
            for (uint256 j; j < cut.functionSelectors.length; j++) {
                bytes4 sel = cut.functionSelectors[j];
                require(
                    ds.selectorToFacet[sel].facetAddress == address(0),
                    "LibDiamond: selector already added"
                );
                ds.selectorToFacet[sel] = FacetAddressAndPosition({
                    facetAddress: cut.facetAddress,
                    functionSelectorPosition: uint96(ds.selectors.length)
                });
                ds.selectors.push(sel);
            }
        }
    }
}

/// The Diamond proxy. All calls are routed through the fallback via
/// delegatecall to whichever facet owns the selector.
contract TileDiamond {
    constructor(address _owner, address _tileFacet, address _erc1155Facet) {
        LibDiamond.setContractOwner(_owner);

        // Register TileFacet selectors
        bytes4[] memory tileSels = new bytes4[](8);
        tileSels[0] = TileFacet.balanceOf.selector;
        tileSels[1] = TileFacet.getTileType.selector;
        tileSels[2] = TileFacet.craftTile.selector;
        tileSels[3] = TileFacet.claimTile.selector;
        tileSels[4] = TileFacet.equipTile.selector;
        tileSels[5] = TileFacet.unequipTile.selector;
        tileSels[6] = TileFacet.addTileTypes.selector;
        tileSels[7] = TileFacet.getCraftQueue.selector;

        // Register ERC1155Facet selectors
        bytes4[] memory ercSels = new bytes4[](4);
        ercSels[0] = ERC1155Facet.safeTransferFrom.selector;
        ercSels[1] = ERC1155Facet.safeBatchTransferFrom.selector;
        ercSels[2] = ERC1155Facet.setApprovalForAll.selector;
        ercSels[3] = ERC1155Facet.isApprovedForAll.selector;

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](2);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: _tileFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: tileSels
        });
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: _erc1155Facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: ercSels
        });

        LibDiamond.diamondCut(cuts, address(0), "");
    }

    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 pos = LibDiamond.DIAMOND_STORAGE_POSITION;
        assembly { ds.slot := pos }

        address facet = ds.selectorToFacet[msg.sig].facetAddress;
        require(facet != address(0), "Diamond: function does not exist");
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

// ============================================================
//  Shared storage — must be kept in sync across all facets
// ============================================================

/// The storage layout lives at slot 0. Every facet that reads or writes
/// state must declare this exact struct so that storage offsets agree.
/// There is no compiler enforcement — a typo here corrupts state silently.
struct TileType {
    uint256 width;
    uint256 height;
    uint256 craftTime;          // blocks until claimable
    uint256 alchemicaCostFud;
    uint256 alchemicaCostFomo;
    uint256 alchemicaCostAlpha;
    uint256 alchemicaCostKek;
}

struct QueueItem {
    uint256 id;
    uint256 readyBlock;
    uint256 tileType;
    bool claimed;
    address owner;
}

struct AppStorage {
    address owner;
    // Tile types registry
    TileType[] tileTypes;
    // Craft queue
    QueueItem[] craftQueue;
    uint256 nextCraftId;
    // ERC1155 balances: owner => tileId => balance
    mapping(address => mapping(uint256 => uint256)) balances;
    // ERC1155 operator approvals
    mapping(address => mapping(address => bool)) operators;
    // Equip tracking: realmId => tileId => count
    mapping(uint256 => mapping(uint256 => uint256)) equipped;
}

library LibAppStorage {
    function store() internal pure returns (AppStorage storage s) {
        assembly { s.slot := 0 }
    }
}

// ============================================================
//  TileFacet — craft queue, tile types, equip/unequip
// ============================================================

contract TileFacet {
    AppStorage internal s;

    modifier onlyOwner() {
        require(msg.sender == s.owner, "TileFacet: not owner");
        _;
    }

    // --- reads ---

    function balanceOf(address _owner, uint256 _id)
        external view returns (uint256)
    {
        return s.balances[_owner][_id];
    }

    function getTileType(uint256 _typeId)
        external view returns (TileType memory)
    {
        require(_typeId < s.tileTypes.length, "TileFacet: invalid type");
        return s.tileTypes[_typeId];
    }

    function getCraftQueue()
        external view returns (QueueItem[] memory out)
    {
        // Return caller's queue items. In production this would be
        // paginated; simplified here for comparison.
        uint256 len = s.craftQueue.length;
        out = new QueueItem[](len);
        uint256 count;
        for (uint256 i; i < len; i++) {
            if (s.craftQueue[i].owner == msg.sender) {
                out[count] = s.craftQueue[i];
                count++;
            }
        }
        assembly { mstore(out, count) }
    }

    // --- writes ---

    function craftTile(uint256 _tileTypeId) external {
        require(
            _tileTypeId < s.tileTypes.length,
            "TileFacet: invalid tile type"
        );
        TileType memory tt = s.tileTypes[_tileTypeId];
        uint256 readyBlock = block.number + tt.craftTime;

        s.craftQueue.push(QueueItem({
            id: s.nextCraftId,
            readyBlock: readyBlock,
            tileType: _tileTypeId,
            claimed: false,
            owner: msg.sender
        }));
        s.nextCraftId++;
    }

    function claimTile(uint256 _queueId) external {
        require(
            _queueId < s.craftQueue.length,
            "TileFacet: invalid queue id"
        );
        QueueItem storage item = s.craftQueue[_queueId];
        require(msg.sender == item.owner, "TileFacet: not owner");
        require(!item.claimed, "TileFacet: already claimed");
        require(
            block.number >= item.readyBlock,
            "TileFacet: not ready"
        );
        item.claimed = true;
        s.balances[msg.sender][item.tileType] += 1;
    }

    function equipTile(
        address _owner,
        uint256 _realmId,
        uint256 _tileId
    ) external {
        require(
            s.balances[_owner][_tileId] >= 1,
            "TileFacet: insufficient balance"
        );
        s.balances[_owner][_tileId] -= 1;
        s.equipped[_realmId][_tileId] += 1;
    }

    function unequipTile(
        address _owner,
        uint256 _realmId,
        uint256 _tileId
    ) external {
        require(
            s.equipped[_realmId][_tileId] >= 1,
            "TileFacet: not equipped"
        );
        s.equipped[_realmId][_tileId] -= 1;
        s.balances[_owner][_tileId] += 1;
    }

    // --- owner admin ---

    function addTileTypes(TileType[] calldata _types) external onlyOwner {
        for (uint256 i; i < _types.length; i++) {
            s.tileTypes.push(_types[i]);
        }
    }
}

// ============================================================
//  ERC1155Facet — token transfers and approvals
// ============================================================

contract ERC1155Facet {
    AppStorage internal s;

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    function isApprovedForAll(address account, address operator)
        external view returns (bool)
    {
        return s.operators[account][operator];
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(msg.sender != operator, "ERC1155: self-approval");
        s.operators[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _value,
        bytes calldata
    ) external {
        require(_to != address(0), "ERC1155: zero address");
        require(
            msg.sender == _from || s.operators[_from][msg.sender],
            "ERC1155: not authorized"
        );

        uint256 bal = s.balances[_from][_id];
        require(bal >= _value, "ERC1155: insufficient balance");
        s.balances[_from][_id] = bal - _value;
        s.balances[_to][_id] += _value;

        emit TransferSingle(msg.sender, _from, _to, _id, _value);
    }

    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata
    ) external {
        require(_to != address(0), "ERC1155: zero address");
        require(
            _ids.length == _values.length,
            "ERC1155: length mismatch"
        );
        require(
            msg.sender == _from || s.operators[_from][msg.sender],
            "ERC1155: not authorized"
        );

        for (uint256 i; i < _ids.length; i++) {
            uint256 bal = s.balances[_from][_ids[i]];
            require(bal >= _values[i], "ERC1155: insufficient balance");
            s.balances[_from][_ids[i]] = bal - _values[i];
            s.balances[_to][_ids[i]] += _values[i];
        }

        emit TransferBatch(msg.sender, _from, _to, _ids, _values);
    }
}
