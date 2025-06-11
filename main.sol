// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

contract Rifa {
    // Variables
    enum State {
        Started,
        Inscriptions,
        Bets,
        Winners,
        Distribution
    }
    State public state;

    address private owner;
    address private delegate;

    uint public finalInscriptionTime;


    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyDelegate() {
        require(msg.sender == delegate);
        _;
    }

    modifier inState(State _state) {
        require(state == _state);
        _;
    }


    // Events
    event inscriptionStarted();


    // Methods
    constructor() {
        owner = msg.sender;
        state = State.Started;
    }

    function setDelegate(
        address _delegate
    )
    onlyOwner()
    inState(State.Started)
    public
    {
        require (_delegate != owner);
        delegate = _delegate;
        if (finalInscriptionTime > 0) {
            state = State.Inscriptions;
            emit inscriptionStarted();
        }
    }

    function setInscriptionTime(
        uint _seconds
    )
    onlyOwner()
    inState(State.Started)
    public
    {
        finalInscriptionTime = block.timestamp + _seconds;
        if (delegate != address(0)) {
            state = State.Inscriptions;
            emit inscriptionStarted();
        }
    }
}