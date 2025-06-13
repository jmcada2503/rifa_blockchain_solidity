// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

contract Rifa {
    enum State {
        Started,
        Inscriptions,
        Canceled,
        Bets,
        Winners,
        Distribution
    }
    State public state;

    address private owner;
    address private delegate;

    uint private finalInscriptionTime;

    struct user {
        uint secretNumber;
        uint attempts;
        bool hasBet;
        bool isCandidate;
    }

    mapping(address => user) private users;
    address[] private userList;

    // Variables para etapa ganadores y distribución
    mapping(address => uint) private chosenNumbers;
    mapping(uint => address) private numberToCandidate;
    uint private candidatesCount;
    uint private candidatesChosenCount;

    uint private mainWinnerNumber;
    uint private secondWinnerNumber;

    uint private inscriptionTotal;
    uint private totalBalance;

    bool private distributionDone;

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

    constructor() {
        owner = msg.sender;
        state = State.Started;
    }

    // Asignar delegado
    function setDelegate(address _delegate)
        public
        onlyOwner
        inState(State.Started)
    {
        require(_delegate != owner, "El delegado debe ser distinto al dueno");
        delegate = _delegate;
        if (finalInscriptionTime > 0) {
            state = State.Inscriptions;
            emit inscriptionStarted();
        }
    }

    // Asignar tiempo de inscripciones
    function setInscriptionTime(uint _seconds)
        public
        onlyOwner
        inState(State.Started)
    {
        finalInscriptionTime = block.timestamp + _seconds;
        if (delegate != address(0)) {
            state = State.Inscriptions;
            emit inscriptionStarted();
        }
    }

    // Inscripción de usuarios
    function register() public payable inState(State.Inscriptions) {
        require(msg.sender != owner, "El dueno no puede inscribirse");
        require(msg.sender != delegate, "El delegado no puede inscribirse");
        require(msg.value == 1 ether, "Debe pagar exactamente 1 Ether");
        require(block.timestamp <= finalInscriptionTime, "Inscripcion cerrada");
        require(users[msg.sender].secretNumber == 0, "Ya estas inscrito");

        uint secret = (uint(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.prevrandao))) % 10) + 1;

        users[msg.sender] = user(secret, 0, false, false);
        userList.push(msg.sender);
    }

    // Ver número secreto (solo delegado)
    function getSecretNumber(address userAddr) public view onlyDelegate returns (uint) {
        return users[userAddr].secretNumber;
    }

    // Abrir apuestas
    function openBets() public inState(State.Inscriptions) {
        require(msg.sender == owner || msg.sender == delegate, "No autorizado");
        require(block.timestamp >= finalInscriptionTime, "Tiempo de inscripcion no ha terminado");

        if (userList.length==0){
            state=State.Canceled;
        }else{
            state = State.Bets;
        }
    }

    // Apostar
    function bet() public payable inState(State.Bets) {
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

    // Adivinar número secreto
    function guessSecretNumber(uint number) public inState(State.Bets) {
        user storage u = users[msg.sender];
        require(u.secretNumber != 0, "No estas inscrito");
        require(u.hasBet, "No has apostado");
        require(u.attempts > 0, "No te quedan intentos");

        u.attempts--;

        if (number == u.secretNumber) {
            u.isCandidate = true;
        }
    }

    // Cerrar apuestas
    function closeBets() public onlyDelegate inState(State.Bets) {
        
        // Contar candidatos
        uint count = 0;
        for (uint i = 0; i < userList.length; i++) {
            if (users[userList[i]].isCandidate) {
                count++;
            }
        }
        candidatesCount = count;

        if (count == 0) {
            state = State.Distribution;
        } else if (count == 1) {
            // Saltar etapa de elección y pasar directamente a distribución
            address soloCandidate;
            for (uint i = 0; i < userList.length; i++) {
                if (users[userList[i]].isCandidate) {
                    soloCandidate = userList[i];
                    break;
                }
            }
            mainWinnerNumber = 1;
            numberToCandidate[1] = soloCandidate;
            state = State.Distribution;
        } else {
            state = State.Winners;
        }
    }

    //Mirar el total de cadndidatos
    function getCandidateCount() public view returns (uint) {
        return candidatesCount;
    }

    // Elegir número por parte del candidato
    function chooseNumber(uint number) public inState(State.Winners) {
        require(users[msg.sender].isCandidate, "No eres candidato");
        require(number >= 1 && number <= candidatesCount, "Numero fuera de rango (Elige entre el 1 y el total de candidatos)");
        require(chosenNumbers[msg.sender] == 0, "Ya elegiste un numero");
        require(numberToCandidate[number] == address(0), "Numero ya fue elegido");

        chosenNumbers[msg.sender] = number;
        numberToCandidate[number] = msg.sender;

        candidatesChosenCount++;
    }

    // Ver número elegido por candidato (solo delegado)
    function getCandidateNumber(address candidate) public view onlyDelegate returns (uint) {
        return chosenNumbers[candidate];
    }

    // Verificar si todos los candidatos eligieron
    function allCandidatesChose() private view returns (bool) {
        return candidatesChosenCount == candidatesCount;
    }

    // Iniciar distribución
    function startDistribution() public onlyDelegate inState(State.Winners) {
        require(allCandidatesChose(), "Faltan candidatos por elegir numero");

        uint baseRandom = uint(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)));
        mainWinnerNumber = (baseRandom % candidatesCount) + 1;

        uint secondRandom = uint(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
        secondWinnerNumber = (secondRandom % candidatesCount) + 1;

        
        uint salt = 0;
        do {
            salt++;
            secondRandom = uint(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, salt)));
            secondWinnerNumber = (secondRandom % candidatesCount) + 1;
        } while (secondWinnerNumber == mainWinnerNumber);
        
        state = State.Distribution;
    }

    // Ver números ganadores (solo delegado)
    function getWinnersNumber()
    onlyDelegate()
    public
    view
    returns (
        uint mainWinnerNumber_,
        uint secondWinnerNumber_
    )
    {
        mainWinnerNumber_ = mainWinnerNumber;
        secondWinnerNumber_ = secondWinnerNumber;
    }

    // Distribuir premios
    function distributePrizes() public onlyDelegate inState(State.Distribution) {
        require(!distributionDone, "Premios ya distribuidos");

        inscriptionTotal = userList.length * 1 ether;
        totalBalance = address(this).balance;
        uint betsTotal = totalBalance - inscriptionTotal;

        if (candidatesCount == 0) {
            // No hubo candidatos, lo apostado va para el dueño
            payable(delegate).transfer(inscriptionTotal);
            payable(owner).transfer(betsTotal);
        } else if (candidatesCount == 1) {
            // Solo un candidato: se lleva el 75% de lo apostado
            address mainWinner = numberToCandidate[mainWinnerNumber];

            uint mainWinnerShare = betsTotal * 75 / 100;
            uint ownerShare = betsTotal - mainWinnerShare;

            payable(delegate).transfer(inscriptionTotal);
            payable(mainWinner).transfer(mainWinnerShare);
            payable(owner).transfer(ownerShare);
        } else {
            // Hay dos o más candidatos: reparto normal
            address mainWinner = numberToCandidate[mainWinnerNumber];
            address secondWinner = numberToCandidate[secondWinnerNumber];

            uint ownerShare = betsTotal * 25 / 100;
            uint mainWinnerShare = betsTotal * 50 / 100;
            uint secondWinnerShare = betsTotal * 25 / 100;

            payable(delegate).transfer(inscriptionTotal);
            payable(owner).transfer(ownerShare);
            payable(mainWinner).transfer(mainWinnerShare);
            payable(secondWinner).transfer(secondWinnerShare);
        }

        distributionDone = true;
    }



    // Ver ganadores
    function getWinners() public view returns (
        address mainWinner,
        uint mainPrize,
        address secondWinner,
        uint secondPrize
    ) {
        require(state == State.Distribution && distributionDone, "Distribucion no realizada");

        uint betsTotal = totalBalance - inscriptionTotal;

        if (candidatesCount == 0) {
            mainWinner = address(0);
            secondWinner = address(0);
            mainPrize = 0;
            secondPrize = 0;
        } else if (candidatesCount == 1) {
            mainWinner = numberToCandidate[mainWinnerNumber];
            secondWinner = address(0);
            mainPrize = betsTotal * 75 / 100;
            secondPrize = 0;
        } else {
            mainWinner = numberToCandidate[mainWinnerNumber];
            secondWinner = numberToCandidate[secondWinnerNumber];

            mainPrize = betsTotal * 50 / 100;
            secondPrize = betsTotal * 25 / 100;
        }
    }

}