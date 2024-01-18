// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./EllipticCurve.sol";

contract ElectionContract {
    uint256 public counter;

    mapping(uint256 => Vote) public votes;
    mapping(address => bool) public voted;

    // secp256r1 eliptik dogrusu icin parametreleri tanimliyoruz
    uint256 private constant N =
        0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551;
    uint256 private constant A =
        0xffffffff00000001000000000000000000000000fffffffffffffffffffffffc;
    uint256 private constant B =
        0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b;
    uint256 private constant P =
        0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff;
    uint256 private constant Gx =
        0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    uint256 private constant Gy =
        0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5;
    Point private G = Point(Gx, Gy); // Generator point

    Point public Y; // Public key, constructor tarafindan set edilecek

    Vote public encryptedSum; //oylarin homomorfik bir sekilde sifrelenip yer alacagi degisken

    constructor(uint256 yx, uint256 yy) {
        require(EllipticCurve.isOnCurve(yx, yy, A, B, P), "Nokta dogruda degil");
        Y = Point(yx, yy);
    }

    struct Vote {
        Point C1;
        Point C2;
        address voter;
    }

    struct Point {
        uint256 x;
        uint256 y;
    }

    // Noktalarin x ve y koordinatlarini EllipticCurve ecAdd fonksiyonuna gonderip toplama islemi yapiyoruz
    function sumPoints(
        Point memory p1, 
        Point memory p2
    ) internal pure returns (Point memory) {
        (uint256 x, uint256 y) = EllipticCurve.ecAdd(
            p1.x,
            p1.y,
            p2.x,
            p2.y,
            A,
            P
        );
        return Point(x, y);
    }

    /*
        OPERAToR İsLEM KODLARI
    */

    // Oylarin toplamini almak icin sumPoints fonksiyonunu kullaniyoruz
    function sumVotes(
        Vote memory v1,
        Vote memory v2
    ) internal pure returns (Vote memory) {
        return Vote(
            sumPoints(v1.C1, v2.C1), 
            sumPoints(v1.C2, v2.C2), 
            address(0));
    }

    // Noktanin x ve y koordinatlarini EllipticCurve ecMultiply fonksiyonuna gonderip carpma islemi yapiyoruz
    function mulPoints(
        Point memory p1,
        uint256 scalar
    ) internal pure returns (Point memory) {
        (uint256 x, uint256 y) = EllipticCurve.ecMultiply(
            scalar,
            p1.x,
            p1.y,
            A,
            P
        );
        return Point(x, y);
    }

    // Oylarin carpimini almak icin mulPoints fonksiyonunu kullaniyoruz
    function mulVotes(
        Vote memory v1,
        uint256 scalar
    ) internal pure returns (Vote memory) {
        return Vote(
            mulPoints(v1.C1, scalar),
            mulPoints(v1.C2, scalar),
            address(0));
    }

    // Noktalarin x ve y koordinatlarini EllipticCurve ecSubstract fonksiyonuna gonderip cikarma islemi yapiyoruz
    function subPoints(
        Point memory p1,
        Point memory p2
    ) internal pure returns (Point memory) {
        (uint256 x, uint256 y) = EllipticCurve.ecSubstract(
            p1.x,
            p1.y,
            p2.x,
            p2.y,
            A,
            P
        );
        return Point(x, y);
    }

    // Noktalarin ayni olup olmadigini kontrol ediyoruz
    function equals(
        Point memory p1,
        Point memory p2
    ) internal pure returns (bool) {
        return(
            // Noktalarin x ve y koordinatlarini keccak256 fonksiyonuna gonderip hash degerlerini karsilastiriyoruz
            keccak256(abi.encodePacked(p1.x, p1.y)) 
            == 
            keccak256(abi.encodePacked(p2.x, p2.y))
        );
    }

    // verify proof fonksiyonu ile oylarin sifrelenmis halinin dogrulugunu kontrol ediyoruz
        function verify_proof(
        Point memory C1,
        Point memory C2,
        uint256[12] memory p
    ) internal view returns (bool) {
        // [0] a0x
        // [1] a0y
        // [2] b0x
        // [3] b0y
        // [4] a1x
        // [5] a1y
        // [6] b1x
        // [7] b1y
        // [8] c0
        // [9] c1
        // [10] f0
        // [11] f1

        bytes32 h = keccak256(
            abi.encodePacked(
                [
                    C1.x,
                    C1.y,
                    C2.x,
                    C2.y,
                    p[0],
                    p[1],
                    p[4],
                    p[5],
                    p[2],
                    p[3],
                    p[6],
                    p[7]
                ]
            )
        );
        uint256 c = uint256(h) % N;
        bool s0 = addmod(p[8], p[9], N) == c;
        bool s1 = equals(
            mulPoints(G, p[10]),
            sumPoints(Point(p[0], p[1]), mulPoints(C1, p[8]))
        );
        bool s2 = equals(
            mulPoints(G, p[11]),
            sumPoints(Point(p[4], p[5]), mulPoints(C1, p[9]))
        );
        bool s3 = equals(
            mulPoints(Y, p[10]),
            sumPoints(Point(p[2], p[3]), mulPoints(C2, p[8]))
        );
        bool s4 = equals(
            mulPoints(Y, p[11]),
            sumPoints(Point(p[6], p[7]), mulPoints(subPoints(C2, G), p[9]))
        );
        return s0 && s1 && s2 && s3 && s4;
    }

    function cast_vote(
        uint256 c1x,
        uint256 c1y,
        uint256 c2x,
        uint256 c2y,
        uint256[12] memory proof
    ) external {
        require(EllipticCurve.isOnCurve(c1x, c1y, A, B, P), "Nokta egride degil");
        require(EllipticCurve.isOnCurve(c2x, c2y, A, B, P), "Nokta egride degil");
        require(!voted[msg.sender], "Zaten oy kullandiniz");
        Point memory C1 = Point(c1x, c1y);
        Point memory C2 = Point(c2x, c2y);
        require(verify_proof(C1, C2, proof), "invalid proof");
        // require(
        //     verify_proof(Point(c1x, c1y), Point(c2x, c2y), proof),
        //     "Oy kaniti dogrulanamadi"
        // );
        

        Vote memory vote = Vote(Point(c1x, c1y), Point(c2x, c2y), msg.sender);

        votes[counter] = vote;
        voted[msg.sender] = true;
        counter++;

        if(encryptedSum.C1.x == 0 && encryptedSum.C1.y == 0 && encryptedSum.C2.x == 0 && encryptedSum.C2.y == 0){
            encryptedSum = vote;
        }else{
            encryptedSum = sumVotes(encryptedSum, vote);
        }
    }

}