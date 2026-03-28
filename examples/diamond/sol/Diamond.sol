// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// EIP-2535 Diamond with two business facets: token balances and governance.
///
/// Based on Nick Mudge's diamond-3-hardhat (MIT). The Diamond proxy, LibDiamond
/// library, and facet infrastructure are included inline so the file is
/// self-contained for benchmarking against the Fe version.
///
/// Reference: https://github.com/mudgen/diamond-3-hardhat

// ============================================================================
// Interfaces
// ============================================================================

interface IDiamondCut {
    enum FacetCutAction { Add, Replace, Remove }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;

    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);
}

interface IDiamondLoupe {
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    function facets() external view returns (Facet[] memory facets_);
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory);
    function facetAddresses() external view returns (address[] memory);
    function facetAddress(bytes4 _functionSelector) external view returns (address);
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC173 {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() external view returns (address);
    function transferOwnership(address _newOwner) external;
}

// ============================================================================
// LibDiamond — selector routing and storage (from diamond-3-hardhat)
// ============================================================================

error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    struct FacetAddressAndPosition {
        address facetAddress;
        uint96 functionSelectorPosition;
    }

    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint256 facetAddressPosition;
    }

    struct DiamondStorage {
        mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
        mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
        address[] facetAddresses;
        mapping(bytes4 => bool) supportedInterfaces;
        address contractOwner;
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly { ds.slot := position }
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setContractOwner(address _newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    function contractOwner() internal view returns (address) {
        return diamondStorage().contractOwner;
    }

    function enforceIsContractOwner() internal view {
        require(msg.sender == diamondStorage().contractOwner, "LibDiamond: Must be contract owner");
    }

    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            IDiamondCut.FacetCutAction action = _diamondCut[facetIndex].action;
            if (action == IDiamondCut.FacetCutAction.Add) {
                addFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Replace) {
                replaceFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Remove) {
                removeFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else {
                revert("LibDiamondCut: Incorrect FacetCutAction");
            }
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
    }

    function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        if (selectorPosition == 0) {
            addFacet(ds, _facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            require(oldFacetAddress == address(0), "LibDiamondCut: Can't add function that already exists");
            addFunction(ds, selector, selectorPosition, _facetAddress);
            selectorPosition++;
        }
    }

    function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        require(_facetAddress != address(0), "LibDiamondCut: Replace facet can't be address(0)");
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        if (selectorPosition == 0) {
            addFacet(ds, _facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            require(oldFacetAddress != _facetAddress, "LibDiamondCut: Can't replace function with same function");
            removeFunction(ds, oldFacetAddress, selector);
            addFunction(ds, selector, selectorPosition, _facetAddress);
            selectorPosition++;
        }
    }

    function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        require(_facetAddress == address(0), "LibDiamondCut: Remove facet address must be address(0)");
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            removeFunction(ds, oldFacetAddress, selector);
        }
    }

    function addFacet(DiamondStorage storage ds, address _facetAddress) internal {
        enforceHasContractCode(_facetAddress, "LibDiamondCut: New facet has no code");
        ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = ds.facetAddresses.length;
        ds.facetAddresses.push(_facetAddress);
    }

    function addFunction(
        DiamondStorage storage ds,
        bytes4 _selector,
        uint96 _selectorPosition,
        address _facetAddress
    ) internal {
        ds.selectorToFacetAndPosition[_selector].functionSelectorPosition = _selectorPosition;
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(_selector);
        ds.selectorToFacetAndPosition[_selector].facetAddress = _facetAddress;
    }

    function removeFunction(DiamondStorage storage ds, address _facetAddress, bytes4 _selector) internal {
        require(_facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");
        require(_facetAddress != address(this), "LibDiamondCut: Can't remove immutable function");
        uint256 selectorPosition = ds.selectorToFacetAndPosition[_selector].functionSelectorPosition;
        uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;
        if (selectorPosition != lastSelectorPosition) {
            bytes4 lastSelector = ds.facetFunctionSelectors[_facetAddress].functionSelectors[lastSelectorPosition];
            ds.facetFunctionSelectors[_facetAddress].functionSelectors[selectorPosition] = lastSelector;
            ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(selectorPosition);
        }
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.pop();
        delete ds.selectorToFacetAndPosition[_selector];

        if (lastSelectorPosition == 0) {
            uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;
            uint256 facetAddressPosition = ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
            if (facetAddressPosition != lastFacetAddressPosition) {
                address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
                ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
                ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;
            }
            ds.facetAddresses.pop();
            delete ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
        }
    }

    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) return;
        enforceHasContractCode(_init, "LibDiamondCut: _init address has no code");
        (bool success, bytes memory error) = _init.delegatecall(_calldata);
        if (!success) {
            if (error.length > 0) {
                assembly {
                    let returndata_size := mload(error)
                    revert(add(32, error), returndata_size)
                }
            } else {
                revert InitializationFunctionReverted(_init, _calldata);
            }
        }
    }

    function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
        uint256 contractSize;
        assembly { contractSize := extcodesize(_contract) }
        require(contractSize > 0, _errorMessage);
    }
}

// ============================================================================
// Diamond proxy
// ============================================================================

contract Diamond {
    constructor(address _contractOwner, address _diamondCutFacet) payable {
        LibDiamond.setContractOwner(_contractOwner);

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = IDiamondCut.diamondCut.selector;
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: _diamondCutFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
        LibDiamond.diamondCut(cut, address(0), "");
    }

    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        assembly { ds.slot := position }
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        require(facet != address(0), "Diamond: Function does not exist");
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

// ============================================================================
// Standard facets (DiamondCut, DiamondLoupe, Ownership)
// ============================================================================

contract DiamondCutFacet is IDiamondCut {
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}

contract DiamondLoupeFacet is IDiamondLoupe, IERC165 {
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numFacets = ds.facetAddresses.length;
        facets_ = new Facet[](numFacets);
        for (uint256 i; i < numFacets; i++) {
            address facetAddress_ = ds.facetAddresses[i];
            facets_[i].facetAddress = facetAddress_;
            facets_[i].functionSelectors = ds.facetFunctionSelectors[facetAddress_].functionSelectors;
        }
    }

    function facetFunctionSelectors(address _facet) external view override returns (bytes4[] memory) {
        return LibDiamond.diamondStorage().facetFunctionSelectors[_facet].functionSelectors;
    }

    function facetAddresses() external view override returns (address[] memory) {
        return LibDiamond.diamondStorage().facetAddresses;
    }

    function facetAddress(bytes4 _functionSelector) external view override returns (address) {
        return LibDiamond.diamondStorage().selectorToFacetAndPosition[_functionSelector].facetAddress;
    }

    function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {
        return LibDiamond.diamondStorage().supportedInterfaces[_interfaceId];
    }
}

contract OwnershipFacet is IERC173 {
    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(_newOwner);
    }

    function owner() external view override returns (address) {
        return LibDiamond.contractOwner();
    }
}

// ============================================================================
// Diamond storage namespaces for business facets
//
// Each facet must use a unique storage slot to avoid collisions. This is the
// manual discipline that Diamond authors must maintain across all facets.
// ============================================================================

library LibTokenStorage {
    bytes32 constant STORAGE_POSITION = keccak256("diamond.app.storage.token");

    struct TokenStorage {
        mapping(address => uint256) balances;
        uint256 totalSupply;
    }

    function store() internal pure returns (TokenStorage storage ts) {
        bytes32 position = STORAGE_POSITION;
        assembly { ts.slot := position }
    }
}

library LibGovernanceStorage {
    bytes32 constant STORAGE_POSITION = keccak256("diamond.app.storage.governance");

    struct Proposal {
        string description;
        uint256 voteStart;
        uint256 voteEnd;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
    }

    struct GovernanceStorage {
        uint256 proposalCount;
        mapping(uint256 => Proposal) proposals;
        // proposalId => voter => hasVoted
        mapping(uint256 => mapping(address => bool)) hasVoted;
        // delegator => delegate
        mapping(address => address) delegates;
        // delegate => delegated vote weight
        mapping(address => uint256) delegatedWeight;
        uint256 votingPeriod; // in blocks
        uint256 quorum;       // minimum total votes for execution
    }

    function store() internal pure returns (GovernanceStorage storage gs) {
        bytes32 position = STORAGE_POSITION;
        assembly { gs.slot := position }
    }
}

// ============================================================================
// Business facet 1: Token balances
// ============================================================================

contract TokenFacet {
    function mint(address to, uint256 amount) external {
        LibDiamond.enforceIsContractOwner();
        LibTokenStorage.TokenStorage storage ts = LibTokenStorage.store();
        ts.balances[to] += amount;
        ts.totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        LibTokenStorage.TokenStorage storage ts = LibTokenStorage.store();
        uint256 bal = ts.balances[msg.sender];
        if (bal < amount) return false;
        ts.balances[msg.sender] = bal - amount;
        ts.balances[to] += amount;
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return LibTokenStorage.store().balances[account];
    }

    function totalSupply() external view returns (uint256) {
        return LibTokenStorage.store().totalSupply;
    }
}

// ============================================================================
// Business facet 2: Governance / voting
// ============================================================================

contract GovernanceFacet {
    function initGovernance(uint256 votingPeriod, uint256 quorum) external {
        LibDiamond.enforceIsContractOwner();
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.store();
        gs.votingPeriod = votingPeriod;
        gs.quorum = quorum;
    }

    function propose(string calldata description) external returns (uint256) {
        // Must hold tokens to propose
        require(
            LibTokenStorage.store().balances[msg.sender] > 0,
            "GovernanceFacet: must hold tokens"
        );
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.store();
        uint256 proposalId = gs.proposalCount;
        gs.proposalCount = proposalId + 1;

        LibGovernanceStorage.Proposal storage p = gs.proposals[proposalId];
        p.description = description;
        p.voteStart = block.number;
        p.voteEnd = block.number + gs.votingPeriod;

        return proposalId;
    }

    function vote(uint256 proposalId, bool support) external {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.store();
        LibGovernanceStorage.Proposal storage p = gs.proposals[proposalId];

        require(block.number >= p.voteStart, "GovernanceFacet: voting not started");
        require(block.number <= p.voteEnd, "GovernanceFacet: voting ended");
        require(!gs.hasVoted[proposalId][msg.sender], "GovernanceFacet: already voted");

        gs.hasVoted[proposalId][msg.sender] = true;

        // Vote weight = own balance + delegated weight
        uint256 weight = LibTokenStorage.store().balances[msg.sender]
                       + gs.delegatedWeight[msg.sender];
        require(weight > 0, "GovernanceFacet: no voting power");

        if (support) {
            p.yesVotes += weight;
        } else {
            p.noVotes += weight;
        }
    }

    function delegate(address to) external {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.store();
        LibTokenStorage.TokenStorage storage ts = LibTokenStorage.store();

        address oldDelegate = gs.delegates[msg.sender];
        uint256 weight = ts.balances[msg.sender];

        // Remove weight from old delegate
        if (oldDelegate != address(0)) {
            gs.delegatedWeight[oldDelegate] -= weight;
        }

        gs.delegates[msg.sender] = to;

        // Add weight to new delegate
        if (to != address(0)) {
            gs.delegatedWeight[to] += weight;
        }
    }

    function execute(uint256 proposalId) external returns (bool) {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.store();
        LibGovernanceStorage.Proposal storage p = gs.proposals[proposalId];

        require(block.number > p.voteEnd, "GovernanceFacet: voting not ended");
        require(!p.executed, "GovernanceFacet: already executed");

        uint256 totalVotes = p.yesVotes + p.noVotes;
        require(totalVotes >= gs.quorum, "GovernanceFacet: quorum not met");

        p.executed = true;
        return p.yesVotes > p.noVotes;
    }

    function getProposal(uint256 proposalId) external view returns (
        uint256 yesVotes,
        uint256 noVotes,
        uint256 voteEnd,
        bool executed
    ) {
        LibGovernanceStorage.Proposal storage p = LibGovernanceStorage.store().proposals[proposalId];
        return (p.yesVotes, p.noVotes, p.voteEnd, p.executed);
    }

    function proposalCount() external view returns (uint256) {
        return LibGovernanceStorage.store().proposalCount;
    }

    function getDelegate(address account) external view returns (address) {
        return LibGovernanceStorage.store().delegates[account];
    }

    function votingPower(address account) external view returns (uint256) {
        return LibTokenStorage.store().balances[account]
             + LibGovernanceStorage.store().delegatedWeight[account];
    }
}

// ============================================================================
// Diamond deployer helper — wires up facets with correct selectors
// ============================================================================

contract DiamondDeployer {
    function deploy(address _owner) external returns (
        address diamond,
        address tokenFacet,
        address governanceFacet
    ) {
        // Deploy all facets
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownerFacet = new OwnershipFacet();
        TokenFacet _tokenFacet = new TokenFacet();
        GovernanceFacet _govFacet = new GovernanceFacet();

        // Deploy the diamond with the cut facet
        Diamond d = new Diamond(_owner, address(cutFacet));

        // Build facet cuts for the remaining facets
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](4);

        // Loupe facet: 5 selectors
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupe.facets.selector;
        loupeSelectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupe.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupe.facetAddress.selector;
        loupeSelectors[4] = IERC165.supportsInterface.selector;
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(loupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        // Ownership facet: 2 selectors
        bytes4[] memory ownerSelectors = new bytes4[](2);
        ownerSelectors[0] = IERC173.transferOwnership.selector;
        ownerSelectors[1] = IERC173.owner.selector;
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownerFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: ownerSelectors
        });

        // Token facet: 4 selectors
        bytes4[] memory tokenSelectors = new bytes4[](4);
        tokenSelectors[0] = TokenFacet.mint.selector;
        tokenSelectors[1] = TokenFacet.transfer.selector;
        tokenSelectors[2] = TokenFacet.balanceOf.selector;
        tokenSelectors[3] = TokenFacet.totalSupply.selector;
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(_tokenFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: tokenSelectors
        });

        // Governance facet: 8 selectors
        bytes4[] memory govSelectors = new bytes4[](8);
        govSelectors[0] = GovernanceFacet.initGovernance.selector;
        govSelectors[1] = GovernanceFacet.propose.selector;
        govSelectors[2] = GovernanceFacet.vote.selector;
        govSelectors[3] = GovernanceFacet.delegate.selector;
        govSelectors[4] = GovernanceFacet.execute.selector;
        govSelectors[5] = GovernanceFacet.getProposal.selector;
        govSelectors[6] = GovernanceFacet.proposalCount.selector;
        govSelectors[7] = GovernanceFacet.getDelegate.selector;
        cuts[3] = IDiamondCut.FacetCut({
            facetAddress: address(_govFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: govSelectors
        });

        // Execute the diamond cut (as the diamond owner)
        IDiamondCut(address(d)).diamondCut(cuts, address(0), "");

        return (address(d), address(_tokenFacet), address(_govFacet));
    }
}
