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


    // Estructura con datos del usuario
    struct user {
        uint secretNumber;
        uint attempts;
        bool hasBet;
        bool isCandidate;
    }
    mapping(address => user) private users;
    address[] public userList;


    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el dueno puede realizar esto");
        _;
    }

    modifier onlyDelegate() {
        require(msg.sender == delegate, "Solo el delegado puede realizar esto");
        _;
    }

    modifier inState(State _state) {
        require(state == _state, "Estado invalido para esta operacion");
        _;
    }


    // Events
    event inscriptionStarted();


    // Methods
    constructor() {
        owner = msg.sender;
        state = State.Started;
    }

    // Funcion para asignar delegado
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

    // Funcion para asignar tiempo de inscripción
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

    // Funcion para que un usuario se inscriba
    function register() public payable inState(State.Inscriptions) {
        require(msg.sender != owner, "El dueno no puede inscribirse");
        require(msg.sender != delegate, "El delegado no puede inscribirse");
        require(msg.value == 1 ether, "Debe pagar exactamente 1 Ether");
        require(block.timestamp <= finalInscriptionTime, "Tiempo de inscripcion finalizado");
        require(users[msg.sender].secretNumber == 0, "Ya estas inscrito");

        uint secret = (uint(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.prevrandao))) % 10) + 1;

        users[msg.sender] = user(secret, 0, false, false);
        userList.push(msg.sender);
    }

    // Funcion para que el delegado vea los números asignados de cada usuario
    function getSecretNumber(address userAddr) public view onlyDelegate returns (uint) {
        return users[userAddr].secretNumber;
    }

    // Funcion para pasar a estado apuestas
    function openBets() public inState(State.Inscriptions){
        require(msg.sender == owner || msg.sender == delegate, "No autorizado");
        require(block.timestamp >= finalInscriptionTime, "Tiempo de inscripcion no ha terminado");

        state = State.Bets;
    }

    // Funcion para apostar
    function bet() public payable inState(State.Bets){
        user storage u = users[msg.sender];

        require(u.secretNumber != 0, "No estas inscrito");
        require(!u.hasBet, "Ya realizaste tu apuesta");

        uint amount = msg.value;
        uint attempts;

        if (amount == 5 ether) attempts = 1;
        else if (amount == 10 ether) attempts = 2;
        else if (amount == 15 ether) attempts = 3;
        else if (amount == 20 ether) attempts = 4;
        else if (amount == 25 ether) attempts = 5;
        else revert("Monto invalido");

        u.attempts = attempts;
        u.hasBet = true;

    }

    //Funcion para intentar adivinar 
    function guessSecretNumber(uint number) public inState(State.Bets) {
        user storage u = users[msg.sender];
        require(u.secretNumber != 0, "No estas inscrito");
        require(u.hasBet, "No has apostado");
        require(u.attempts > 0, "No te quedan intentos");

        u.attempts --;

        if (number == u.secretNumber){ 
        u.isCandidate = true;
        }
    }

    //Funcion para cerrar apuestas
    function closeBets() public onlyDelegate inState(State.Bets){
        state = State.Winners;
    }

}