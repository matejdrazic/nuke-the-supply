// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
// ugovor je očišćen svega vezano za uniswap

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract NukeTheSupply is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    ICBM public icbmToken;
    Warhead public whToken;
    uint256 public INITIAL_ICBM_SUPPLY = 830_000_000 * 10 ** 18; // ukupni ICBM supply
    uint256 public INITIAL_WH_SUPPLY = 1_000 * 10 ** 18; // početni WH supply
    uint256 public remainingSupply = 730_000_000 * 10 ** 18; // supply ICBM tokena koji ostane nakon što se 100M pošalje kreatoru od INITIAL_ICBM_SUPPLY
        // kasnije se koristi kao informacija koliko je ICBM tokena ostalo u ugovoru,
        // iako je za stvarno ta količina veća, jer dio su i korisnikovi ICBMovi u "arm" stanju
    uint256 public constant DEFAULT_SELL = 2_000_000 * 10 ** 18; // preostali supply podijeljen na 365 dana
    uint256 public totalArmedICBMs; // ukupna količina korisnikovih ICBM tokena u "arm" stanju
    uint256 public warheadBought; // ukupna količina WH tokena koju je NTS ugovor kupio, since deployment
    uint256 public totalBurned; // ukupna količina ICBM tokena koju su korisnici burnali koristeći "nuke" funkciju, since deployment
    uint256 public totalSold; // ukupna količina ICBM tokena koju je NTS ugovor prodao, since deployment
    uint256 public day; // varijabla potrebna za računanje količine za prodaju
    uint256 public deploymentTime; // potrebno za postavljanje uvjeta za prvi poziv sell funkciji i faze rada ugovora
    uint256 public lastSellTimestamp; // potrebno za postavljanje svih drugih uvjeta za sell funkciju
    uint256 public constant PREPARATION_DURATION = 48 hours; // promijeniti u 2 min za potrebe testiranja
    uint256 public constant OPERATIONS_DURATION = 365 days; // period tokom kojeg ugovor prodaje ICBM tokene
    uint256 public constant ARM_DURATION = 24 hours; // vremenski period trajanja "arm" stanja korisnikovih ICBM tokena
    uint256 public constant SELL_INTERVAL = 24 hours; // vremenski period potreban da se opet može pozvati "sell" funkcija
    address public constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // Wrapped ETH (sepolia)
    // struct i mapping za spremanje batch-eva korisnikovih ICBM količina koje je stavio u "arm"

    struct ArmBatch {
        uint256 amount;
        uint256 endTime;
    }

    mapping(address => ArmBatch[]) public userArmBatches;

    // eventi
    event Armed(address indexed user, uint256 amount, uint256 endTime);
    event Nuked(address indexed user, uint256 icbmAmount, uint256 burnedAmount, uint256 whMinted);
    event Sold(uint256 day, uint256 icbmSold, uint256 ethReceived, uint256 ethKept);
    event Bought(uint256 day, uint256 warheadBought);

    // uvjeti vezani za faze rada ugovora
    modifier inPreparationPhase() { // Matej: ovo se ne koristi jel?
        require(block.timestamp < deploymentTime + PREPARATION_DURATION, "Preparation phase ended");
        _;
    }

    modifier inOperationsPhase() {
        require(block.timestamp >= deploymentTime + PREPARATION_DURATION, "Operations phase not started");
        _;
    }

    constructor() Ownable(msg.sender) {
        deploymentTime = block.timestamp;
        day = 1;
        lastSellTimestamp = deploymentTime + PREPARATION_DURATION; // postavljanje timestampa prije kojeg se ne može zvati sell funkcija
        icbmToken = new ICBM();
        whToken = new Warhead();
        icbmToken.transfer(owner(), 100_000_000 * 10 ** 18); // kreatoru ide 100M ICBM tokena da napravi trading par ICBM/WETH na uniswapu v3
        whToken.transfer(owner(), INITIAL_WH_SUPPLY); // kreatoru ide sav inicijalni supply za WH/WETH trading par
    }
    ////////////// funkcija kojom korisnici stavljaju svoje ICBM tokene u "arm mode"
    ////////////// ustvari šalju ICBM tokene u NTS ugovor (jednostavnije od nekakve staking mehanike)

    function arm(uint256 amount) external nonReentrant {
        require(day < 364, "Arm phase over"); // korisnici završavaju sa nukiranjem dan prije nego contract završi sa dnevnim prodajama
        require(amount > 0, "Amount must be greater than 0");
        require(icbmToken.transferFrom(msg.sender, address(this), amount), "Transfer failed"); // korisnici salju svoje ICBM tokene u NTS ugovor
        ArmBatch memory newBatch = ArmBatch({amount: amount, endTime: block.timestamp + ARM_DURATION});
        userArmBatches[msg.sender].push(newBatch);
        totalArmedICBMs += amount;
        emit Armed(msg.sender, amount, block.timestamp + ARM_DURATION);
    }
    ////////////// funkcija kojom korisnici nukiraju dio supply-a kojeg NTS ugovor drži, pri tom dobivaju svoje ICBM-ove natrag plus svježe
    ////////////// mintane WH tokene

    function nuke() external nonReentrant {
        ArmBatch[] storage batches = userArmBatches[msg.sender];
        uint256 totalICBMToReturn;
        uint256 totalICBMBurned;
        for (uint256 i = 0; i < batches.length;) {
            if (block.timestamp >= batches[i].endTime) {
                uint256 icbmAmount = batches[i].amount;
                uint256 burnAmount = icbmAmount / 10;
                totalICBMToReturn += icbmAmount;
                totalICBMBurned += burnAmount;
                remainingSupply -= burnAmount;
                totalBurned += burnAmount; // Matej: Buts its not really burned?
                totalArmedICBMs -= icbmAmount;
                whToken.mint(msg.sender, burnAmount);
                emit Nuked(msg.sender, icbmAmount, burnAmount, burnAmount);
                batches[i] = batches[batches.length - 1];
                batches.pop();
            } else {
                i++;
            }
        }
        require(totalICBMToReturn > 0, "No batches ready");
        require(icbmToken.transfer(msg.sender, totalICBMToReturn), "Transfer failed");
    }

    /////////// funkcija koju može pozvati bilo tko, svaka 24 sata, računa količinu ICBM-a za prodaju, dobiveni WETH koristi za kupnju WH tokena
    /////////// nagrađuje pozivatelja funkcije sa 0.001% supply-a WH tokena, minta WH i šalje ih pozivatelju funkcije
    function sell() external inOperationsPhase nonReentrant {
        require(block.timestamp >= lastSellTimestamp, "Not time yet");
        require(day <= 365, "Sell period ended");

        uint256 dailySell =
            (DEFAULT_SELL * day) > (totalSold + totalBurned) ? (DEFAULT_SELL * day) - (totalSold + totalBurned) : 0;

        if (dailySell > 0 && dailySell <= remainingSupply) { // remainingSupply treba dohvatit sa ugovora, kolko ugovora ima ICBM tokena
            remainingSupply -= dailySell;
            totalSold += dailySell;

            /*
    ovdje ideu swapovi, izračunata količina (dailySell) prodaje se za WETH, WETH se potom koristi za kupnju WH tokena, dobiveni WH token šalje se na burn adresu
            */


            // nagrada za pozivanje funkcije dodjeljuje se pozivatelju funkcije
            uint256 whSupply = whToken.totalSupply();
            uint256 rewardAmount = (whSupply * 1) / 100000; // 0.001% od trenutnog WH supplya
            if (rewardAmount > 0) {
                whToken.mint(msg.sender, rewardAmount);
            }
            day++; // postavljanje day varijable za sljedeću kalkulaciju u sell funkciji
            lastSellTimestamp = block.timestamp + SELL_INTERVAL; // postavljanje novog timestampa prije kojeg se sell funkcija ne može pozvati
        }
    }

    /////////////// view funkcije za prikazivanje na web-stranici projekta
    // korisnikove varijable
    function getUserArmedICBM(address user) external view returns (uint256) {
        // količina ICBM-a u "arm" modu
        ArmBatch[] storage batches = userArmBatches[user];
        uint256 totalArmed;
        for (uint256 i = 0; i < batches.length; i++) {
            totalArmed += batches[i].amount;
        }
        return totalArmed;
    }

    function getUserReadyToNuke(address user) external view returns (uint256) {
        // količina ICBM-a koju korisnik ima spremnu za "nukiranje"
        ArmBatch[] storage batches = userArmBatches[user];
        uint256 totalReady;
        for (uint256 i = 0; i < batches.length; i++) {
            if (block.timestamp >= batches[i].endTime) {
                totalReady += batches[i].amount;
            }
        }
        return totalReady;
    }
    ////////////// globalne varijable

    function getTotalBurned() external view returns (uint256) {
        return totalBurned;
    }

    function getTotalSold() external view returns (uint256) {
        return totalSold;
    }

    function getCurrentDay() external view returns (uint256) {
        return day;
    }

    function getRemainingSupply() external view returns (uint256) {
        return remainingSupply;
    }

    function getDailySell() external view returns (uint256) {
        return (DEFAULT_SELL * day) > (totalSold + totalBurned) ? (DEFAULT_SELL * day) - (totalSold + totalBurned) : 0;
    }
}

// ICBM i WH ugovori

contract ICBM is ERC20 { // Burnable
    constructor() ERC20("ICBM", "ICBM") {
        _mint(msg.sender, 830_000_000 * 10 ** 18);
    }
}

contract Warhead is ERC20 { // Burnable
    address public minter;

    constructor() ERC20("Warhead", "WH") {
        _mint(msg.sender, 1_000 * 10 ** 18);
        minter = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "Only minter can mint");
        _mint(to, amount);
    }
}


/**
 * Evo! Ovo je plod mog razmišljanja kako učiniti nešto novo i zabavno na blockchainu, 
 * a opet da ima inovativnu "tokenomiju", jer ljudi jako pate na to :) Kad malo bolje pogledam, 
 * nije contract baš ni jednostavan, pa ću pokušati što sažetije objasniti što radi:

Zamislio sam svojevrsnu "igru rata" na blockchainu između korisnika i 
pametnog ugovora (zvanog NTS, iliti "nuke the supply"), gdje pametni ugovor ima zadatak 
prodati supply ICBM tokena kroz 365 dana, a korisnici će koristiti funkcije namijenjene da to spriječe.

Contract minta dva coina, ICBM (ICBM) i WH (Warhead). ICBM supply je 830M coinova, nakon deploya, 
100M ide kreatoru, 730M ostaje u NTS ugovoru. Također, minta se 1000 WH tokena, samo da bi se mogao 
napraviti trading par. Nakon deploya, ja bi ručno napravio ICBM/WETH i WH/WETH uniswap v3 parove.
Kako sam rekao, dnevna količina za prodaju je defaultSell (830M / 365 dana), 2M dnevno.

Od trenutka deploya, počinje "preparation phase" i traje 48 sati. Za to vrijeme contract ne odrađuje dnevne prodaje, 
ali korisnici mogu koristiti svoje funkcije, "arm" i "nuke". 
nakon "preparation phase"-a, počinje "operations phase" i traje 365 dana (to su tih 365 dana gdje NTS contract 
prodaje preostali supply svaki dan.

ovo su tri osnovne funkcije:
- funkcija "arm" odabranu količinu ICBM tokena od korisnika šalje u contract na minimalno 24 sata, (naoružavanje raketa) - 
    tokom tog vremena korisnici ne mogu do tih tokena. 
- funkcija "nuke" - da bi korisnici dobili svoje ICBM tokene natrag, pokreću "nuke" funkciju, kojom uništavaju 
dio supply-a ICBM-a koju drži NTS contract i za to bivaju nagrađeni Warhead tokenom. 
odnos ICBM iskorišteni za "nukiranje" i ICBM uništeni u NTS contractu je 10:1, a nagrada u Warhead tokenu je 1:1, 
po jedan Warhead token kojeg NTS contract minta i šalje korisniku, za jedan uništeni ICBM token iz preostalog supply-a.

 funkcija "sell": ovu funkciju sam zamislio kao automatsku, da ju ChainLink keeper izvodi ali sam od toga odustao 
 pa sam odlučio da ju pokreću korisnici i za to bivaju nagrađeni svježe mintanim WH tokenom
NTS contract prvo računa količinu za prodati tog dana i koristi formulu:

dailySell = (defaultSell * day) - (totalSold + totalBurned)

totalSold i totalBurned varijable predstavljaju sveukupnu količinu koju je NTS contract prodao od početka i sveukupnu 
količinu koju su korisnici "iznukirali" od početka. Ta formula, omogućava da NTS contract uopće ni ne proda ništa, ako su 
korisnici bili vrijedni i marljivo nukirali protekli dan, ukoliko dailySell bude 0 ili manji od nule.

NTS kontrakt bi, ako je dailySell >0, izračunatu količinu ICBM tokena prodao na uniswapu.
Potom bi "zarađeni" WETH iskoristio za kupnju Warhead tokena
Zatim bi kupljeni Warhead token "burnao"
I na kraju, za nagradu onome tko je izvršio "sell" funkciju (makar ne bilo prodaje ICBM-a), NTS bi izmintao i poslao 
Warhead token u količini 0.001% trenutnog Warhead supply-a kao kompenzaciju.

Eto.. tako sam ja to nekako zamislio, kao igru na blockchainu, NTS ugovor želi prodati ICBM supply, korisnici to žele spriječiti, 
budu li dobri, dobiju Warhead za nagradu. Ne budu li uspjevali, ugovor će pumpati cijenu Warheada 
pa da dobiju warhead, morat će nukirati... Kreirao sam nekakvu push-pull mehaniku između ICBM i Warhead tokena izgleda, 
možda ljudima bude zanimljivo. Oće bit šta od ovog?

 */