// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

library EllipticCurve {

    /// @dev Bir sayinin oklid yontemi ile modula tersi
    /// @param _x x sayisi
    /// @param _p modula
    /// @return x*t = 1 (mod _p) esitligini saglayan t degeri
    function inverseMod(uint256 _x, uint256 _p) internal pure returns (uint256) {
        require(_x != 0 && _x != _p && _p != 0, "Invalid number");
        uint256 q = 0;
        uint256 newT = 1;
        uint256 r = _p;
        uint256 t;
        while (_x != 0) {
            t = r / _x;
            (q, newT) = (newT, addmod(q, (_p - mulmod(t, newT, _p)), _p));
            (r, _x) = (_x, r - t * _x);
        }

        return q;
    }

    /// @dev Moduler us alma, b^e % m
    /// @param b sayi.
    /// @param e us.
    /// @param m modula.
    /// @return r esitligi saglayan r = b**e (mod m)
    function expMod(uint b, uint e, uint m) internal pure returns (uint256) {
        if (b == 0)
            return 0;
        if (e == 0)
            return 1;
        if (m == 0)
            revert();
        uint256 r = 1;
        uint bit = 2 ** 255;
        assembly {
            for {}  iszero(iszero(bit)) {} {
                // jumpi(end, iszero(bit))
                r := mulmod(mulmod(r, r, m), exp(b, iszero(iszero(and(e, bit)))), m)
                r := mulmod(mulmod(r, r, m), exp(b, iszero(iszero(and(e, div(bit, 2))))), m)
                r := mulmod(mulmod(r, r, m), exp(b, iszero(iszero(and(e, div(bit, 4))))), m)
                r := mulmod(mulmod(r, r, m), exp(b, iszero(iszero(and(e, div(bit, 8))))), m)
                bit := div(bit, 16)
                // jump(loop)
                }
        }
        return r;
    }

    /// @dev Jacobian koordinatlarinda ifade edilen bir x,y,z noktasini affine koordinatlarina donusturur x,y,1
    /// @param _x x'in koordinati
    /// @param _y y'nin koordinati
    /// @param _z z'nin koordinati
    /// @param _p modula
    /// @return (x', y') affine koordinatlari
    function convertToAffine(
        uint256 _x,
        uint256 _y,
        uint256 _z,
        uint256 _p
    ) internal pure returns (uint256, uint256) {
        uint256 zInverse = inverseMod(_z, _p);
        uint256 zInverse2 = mulmod(zInverse, zInverse, _p);
        uint256 x2 = mulmod(_x, zInverse2, _p);
        uint256 y2 = mulmod(_y, mulmod(zInverse, zInverse2, _p), _p);

        return (x2, y2);
    }

    /// @dev x,y noktasinin a,b ve p ile olusturulan egride olup olmadigini kontrol eder
    /// @param _x x'in koordinati
    /// @param _y y'nin koordinati
    /// @param _a egrinin sabiti
    /// @param _b egrinin sabiti
    /// @param _p modula
    /// @return eger x, y egri uzerinde ise true degilse false dondurur
    function isOnCurve(
    uint _x,
    uint _y,
    uint _a,
    uint _b,
    uint _p
    ) internal pure returns (bool) {
        if (_x == 0 || _y == 0 || _x >= _p || _y >= _p) {
            return false;
        }

        // y^2
        uint left = expMod(_y, 2, _p);

        // x^3
        uint right = expMod(_x, 3, _p);
        if(_a != 0) {
            // x^3 + a*x
            right = addmod(right, mulmod(_a, _x, _p), _p);
        }
        if(_b != 0) {
            // x^3 + a*x + b
            right = addmod(right, _b, _p);
        }
        return left == right;
    }

    /// @dev Jacobian koordinat sistemindeki iki noktayi toplar
    /// @param _x1 P1'in x koordinati
    /// @param _y1 P1'in y koordinati
    /// @param _z1 P1'in z koordinati
    /// @param _x2 P2'nin x koordinati
    /// @param _y2 P2'nin y koordinati
    /// @param _z2 P2'nin z koordinati
    /// @param _p modula
    /// @return Jacobian koordinat sisteminde (qx, qy, qz) dondurur 
    function jacAdd(
        uint256 _x1,
        uint256 _y1,
        uint256 _z1,
        uint256 _x2,
        uint256 _y2,
        uint256 _z2,
        uint256 _p
    ) internal pure returns (uint256, uint256, uint256) {
        if (_x1 == 0 && _y1 == 0) return (_x2, _y2, _z2);
        if (_x2 == 0 && _y2 == 0) return (_x1, _y1, _z1);

        // Belirtilen makalede'nin 5. Sectionundaki denkleme gore yapiyi olusturuyoruz https://pdfs.semanticscholar.org/5c64/29952e08025a9649c2b0ba32518e9a7fb5c2.pdf
        uint[4] memory zs; // z1^2, z1^3, z2^2, z2^3
        zs[0] = mulmod(_z1, _z1, _p);
        zs[1] = mulmod(_z1, zs[0], _p);
        zs[2] = mulmod(_z2, _z2, _p);
        zs[3] = mulmod(_z2, zs[2], _p);

        // u1, s1, u2, s2
        zs = [
            mulmod(_x1, zs[2], _p),
            mulmod(_y1, zs[3], _p),
            mulmod(_x2, zs[0], _p),
            mulmod(_y2, zs[1], _p)
        ];

        // zs[0] == zs[2] && zs[1] == zs[3] olabilme ihtimalindan dolayi bu kosulda jacDouble kullanilmasi daha saglikli olur
        require(
            zs[0] != zs[2] || zs[1] != zs[3],
            "Use jacDouble function instead"
        );

        uint[4] memory hr;
        //h
        hr[0] = addmod(zs[2], _p - zs[0], _p);
        //r
        hr[1] = addmod(zs[3], _p - zs[1], _p);
        //h^2
        hr[2] = mulmod(hr[0], hr[0], _p);
        // h^3
        hr[3] = mulmod(hr[2], hr[0], _p);
        // qx = -h^3  -2u1h^2+r^2
        uint256 qx = addmod(mulmod(hr[1], hr[1], _p), _p - hr[3], _p);
        qx = addmod(qx, _p - mulmod(2, mulmod(zs[0], hr[2], _p), _p), _p);
        // qy = -s1*z1*h^3+r(u1*h^2 -x^3)
        uint256 qy = mulmod(
            hr[1],
            addmod(mulmod(zs[0], hr[2], _p), _p - qx, _p),
            _p
        );
        qy = addmod(qy, _p - mulmod(zs[1], hr[3], _p), _p);
        // qz = h*z1*z2
        uint256 qz = mulmod(hr[0], mulmod(_z1, _z2, _p), _p);
        return (qx, qy, qz);
    }

    /// @dev Noktayi ikiye katlar (x, y, z).
    /// @param _x P1'in x koordinati
    /// @param _y P1'in y koordinati
    /// @param _z P1'in z koordinati
    /// @param _a equation egri denklemindeki a degeri
    /// @param _p the modulus
    /// @return (qx, qy, qz) 2P in Jacobian
    function jacDouble(
        uint256 _x,
        uint256 _y,
        uint256 _z,
        uint256 _a,
        uint256 _p
    ) internal pure returns (uint256, uint256, uint256) {
        if (_z == 0) return (_x, _y, _z);

        // Yukarida belirttigimiz makalenin ayni section'unu kullaniyoruz denklem icin
        // x, y, z _x, _y _z'nin karelerini temsil ediyor
        uint256 x = mulmod(_x, _x, _p); //x1^2
        uint256 y = mulmod(_y, _y, _p); //y1^2
        uint256 z = mulmod(_z, _z, _p); //z1^2

        // s
        uint s = mulmod(4, mulmod(_x, y, _p), _p);
        // m
        uint m = addmod(
            mulmod(3, x, _p),
            mulmod(_a, mulmod(z, z, _p), _p),
            _p
        );


        // x, y, z'yi qx, qy, qz olacak sekilde gaz maliyetini arttirmamak icin farkli bir degisken kullanmadan
        // yeniden atiyoruz
        // qx = -2S + M^2
        x = addmod(mulmod(m, m, _p), _p - addmod(s, s, _p), _p);
        // qy = -8*y1^4 + M(S-T)
        y = addmod(
            mulmod(m, addmod(s, _p - x, _p), _p),
            _p - mulmod(8, mulmod(y, y, _p), _p),
            _p
        );
        // qz = 2*y1*z1
        z = mulmod(2, mulmod(_y, _z, _p), _p);

        return (x, y, z);
    }

    /// @dev (x, y, z) noktasini d ile carp
    /// @param _d carpilacak sayi
    /// @param _x P1'in x koordinati
    /// @param _y P1'in y koordinati
    /// @param _z P1'in z koordinati
    /// @param _a egrinin sabiti
    /// @param _p modula
    /// @return Jacobian koordinat sisteminde (qx, qy, qz) d*P1
    function jacMul(
        uint256 _d,
        uint256 _x,
        uint256 _y,
        uint256 _z,
        uint256 _a,
        uint256 _p
    ) internal pure returns (uint256, uint256, uint256) {
        if (_d == 0) {
            return (_x, _y, _z);
        }

        uint256 remaining = _d;
        uint256 qx = 0;
        uint256 qy = 0;
        uint256 qz = 1;

        // İkiye katla ve topla algoritmasi
        while (remaining != 0) {
            // son bitinde 1 varsa (tekse) toplama islemi gerceklestirilir
            if ((remaining & 1) != 0) {
                (qx, qy, qz) = jacAdd(qx, qy, qz, _x, _y, _z, _p);
            }
            // ardindan remaining pozitif olur
            // Noktayi ikiye katlayip remaining'i 2'ye bolersek dogru islem yapmis oluruz (7/2=3) gibi
            remaining = remaining / 2;
            (_x, _y, _z) = jacDouble(_x, _y, _z, _a, _p);
        }
        return (qx, qy, qz);
    }

    /// @dev (x, y) noktasinin tersini (x,-y) hesaplar
    /// @param _x x'in koordinati
    /// @param _y y'nin koordinati
    /// @param _p modula
    /// @return x , y'nin tersi (x, -y)  
    function ecInverse(
        uint256 _x,
        uint256 _y,
        uint256 _p
    ) internal pure returns (uint256 x, uint256 y) {
        return (_x, (_p - _y) % _p);
    }

    /// @dev İki noktayi (x1, y1) (x2, y2) affine koordinat sisteminde toplar
    /// @param _x1 P1'in x koordinati
    /// @param _y1 P1'in y koordinati
    /// @param _x2 P2'nin x koordinati
    /// @param _y2 P2'nin y koordinati
    /// @param _a egrinin sabiti
    /// @param _p modula
    /// @return (qx, qy) = P1+P2 esitligini affine koordinat sisteminde dondurur
    function ecAdd(
        uint256 _x1,
        uint256 _y1,
        uint256 _x2,
        uint256 _y2,
        uint256 _a,
        uint256 _p
    ) internal pure returns (uint256, uint256) {
        uint x = 0;
        uint y = 0;
        uint z = 0;

        // x1 x2'ye esitse ikiye katla degilse ekle
        if (_x1 == _x2) {
            // y1 = -y2 mod p
            if (addmod(_y1, _y2, _p) == 0) {
                return (0, 0);
            } else {
                // P1 = P2
                (x, y, z) = jacDouble(_x1, _y1, 1, _a, _p);
            }
        } else {
            (x, y, z) = jacAdd(_x1, _y1, 1, _x2, _y2, 1, _p);
        }
        // Jacobian koordinat sisteminden Affine koordinat sistemine cevir
        // Affine'e cevirmek icin z yi 1 vermeliyiz
        // z degeri onceki fonksiyonlardan 1 oldu
        return convertToAffine(x, y, z, _p);
    }

    /// @dev İki noktayi affine koordinat duzleminde birbirinden cikarir
    /// @param _x1 P1'in x koordinati
    /// @param _y1 P1'in y koordinati
    /// @param _x2 P2'nin x koordinati
    /// @param _y2 P2'nin y koordinati
    /// @param _a egrinin sabiti
    /// @param _p modula
    /// @return affine koordinatlarinda (qx, qy) = P1-P2 esitligini saglayan (qx, qy)'yi dondurur
    function ecSubstract(
        uint256 _x1,
        uint256 _y1,
        uint256 _x2,
        uint256 _y2,
        uint256 _a,
        uint256 _p
    ) internal pure returns (uint256, uint256) {
        // P2'yi tersine cevir
        (uint256 x, uint256 y) = ecInverse(_x2, _y2, _p);
        // P1 + (-P2)
        return ecAdd(_x1, _y1, x, y, _a, _p);
    }

    /// @dev (x1, y1, z1) noktasini affine koordinatlarinda k ile carpar
    /// @param _k carpim sayisi
    /// @param _x P1'de x koordinati
    /// @param _y P1'de y koordinati
    /// @param _a egrinin sabiti
    /// @param _p modula
    /// @return affine koordinatlarinda (qx, qy) = d*P ' yi verir
    function ecMultiply(
        uint256 _k,
        uint256 _x,
        uint256 _y,
        uint256 _a,
        uint256 _p
    ) internal pure returns (uint256, uint256) {
        // Jacobian multiplication
        (uint256 x1, uint256 y1, uint256 z1) = jacMul(_k, _x, _y, 1, _a, _p);
        // Get back to affine
        return convertToAffine(x1, y1, z1, _p);
    }

}