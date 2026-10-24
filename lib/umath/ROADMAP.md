# umath — Roadmap

**Part of:** umath — unified math library

The plan for making umath a complete mathematics library for Utkarsha OS,
from everyday formulas to numerical methods and machine learning. Every
item is built the same way as the rest of umath:
- pure x86-64 assembly;
- f32 and f64 versions (or exact integers);
- array variants where they make sense;
- verified by `tests/run_tests.sh`, both natively and on the SSE2
  baseline.

umath is pure mathematics. Physics and other science formulas, including
physical unit conversions, belong to the separate science library, usci,
which uses umath for its math.

Legend: ✅ done · ☐ planned

---

## Build order

| Stage | Groups | Why this order |
|---|---|---|
| 1 | Foundations (done), B number basics, N number representation, A everyday math, C algebra, D geometry, E trigonometry | the school-level base everything else uses |
| 2 | F linear algebra, I complex numbers, H statistics, K combinatorics, O abstract algebra, P information and coding | needed by graphics, signal processing, cryptography and data work |
| 3 | G numerical methods, J special functions | calculus-level tools built on stages 1–2 |
| 4 | M machine learning | last: built on everything above |

---

## Foundations (done)

| Area | Functions | Module |
|---|---|---|
| Arithmetic and rounding | ✅ abs, neg, sign, copysign, min, max, clamp, floor, ceil, trunc, round, fractional part, reciprocal, fdim, isnan, isinf | `scalar/` |
| IEEE 754 helpers | ✅ fmod, remainder, remquo, frexp, ilogb, logb, modf, nextafter, nextup, nextdown, scalbn/ldexp, fma | `scalar/`, `math_fn/` |
| Roots, powers, logs | ✅ sqrt, cbrt, hypot, exp, exp2, exp10, expm1, log, log2, log10, log1p, pow, polyval | `math_fn/` |
| Trigonometry | ✅ sin, cos, tan, asin, acos, atan, atan2 | `math_fn/` |
| Hyperbolic | ✅ sinh, cosh, tanh, asinh, acosh, atanh | `math_fn/` |
| Special functions | ✅ erf, erfc, tgamma, lgamma (+ sign) | `math_fn/` |
| Integers | ✅ gcd (HCF), lcm, extended gcd, isqrt, icbrt, ilog2, ilog10, is_square, ipow, mulmod, powmod, modinv, is_prime, next_prime, factorial, binomial | `integer/` |
| Sums and statistics | ✅ sum, mean, dot, sum of squares, product, exact integer sums, Kahan and pairwise sums, Welford mean/variance, logsumexp | `reduce/`, `stability/` |
| Geometry | ✅ 2D affine transforms, quadratic/cubic Bézier curves, elliptical arcs | `geom/` |
| Random numbers | ✅ xoshiro256**, splitmix64 seeding, uniform reals | `random/` |
| Infrastructure | ✅ bit operations, 213-format dtype system, memory operations and allocators, CPU feature detection with SSE2 fallbacks | `bits/`, `dtype/`, `memory/`, `cpuid/` |

---

## Stage 1

### N. Number representation and precision

| Group | Formulas |
|---|---|
| Exact decimals for money | ☐ fixed-point decimal (e.g. 2 or 4 places): add, subtract, multiply, divide · rounding modes (half up, half even / banker's, down, up) · so interest and tax come out to the exact paisa/cent |
| Number ↔ text | ☐ integer ↔ decimal string (any base) · float → shortest round-trip decimal string · decimal string → correctly rounded float · formatting with a fixed number of digits |
| Reduced-precision floats | ✅ fp16/bf16/fp8 formats described in `dtype/` · ☐ correctly rounded conversions to/from f32 · arithmetic on fp16 and bf16 |
| Higher precision | ☐ double-double arithmetic (about 32 digits) · arbitrary-precision floats (with the big integers of B) · correctly rounded results checked against them |
| Interval arithmetic | ☐ intervals [lo, hi] with outward rounding: add, subtract, multiply, divide, sqrt, exp, log — guaranteed bounds |
| Comparisons | ☐ approximately equal (absolute, relative, ULP tolerance) · ULP distance · total ordering of floats |

### A. Everyday and commercial math

| Group | Formulas |
|---|---|
| Interest | ☐ simple interest P·R·T/100 · compound interest P(1 + r/n)^(nt) · continuous compounding P·e^(rt) · effective annual rate (1 + r/n)ⁿ − 1 · rule of 72 · doubling time ln 2 / ln(1 + r) |
| Discounting | ☐ true discount · banker's discount · present worth · simple/compound discount |
| Loans and annuities | ☐ EMI P·r(1+r)ⁿ / ((1+r)ⁿ − 1) · amortization schedule · outstanding balance · present value of an annuity PMT·(1 − (1+r)⁻ⁿ)/r · future value PMT·((1+r)ⁿ − 1)/r · perpetuity PMT/r · sinking fund |
| Investment | ☐ NPV Σ CFₜ/(1+r)ᵗ · IRR (root of NPV = 0) · CAGR (end/start)^(1/n) − 1 · ROI · payback period · real rate (1 + n)/(1 + i) − 1 |
| Bonds and shares | ☐ bond price from coupons and yield · yield to maturity · current yield · Macaulay and modified duration · dividend yield · earnings per share |
| Business | ☐ break-even point · contribution margin · annuity due vs ordinary annuity · loans with changing rates · currency conversion (with exact decimal rounding, see N) |
| Depreciation | ☐ straight-line (C − S)/n · reducing balance C(1 − r)ⁿ · sum-of-years' digits |
| Percentages | ☐ x% of y · percent change · percentage points · reverse percentage · successive changes (1 + a)(1 + b) − 1 |
| Profit and loss | ☐ profit/loss and % · cost price ↔ selling price · marked price · discount % · successive discounts · markup vs margin |
| Tax and billing | ☐ tax add/remove (inclusive ↔ exclusive) · commission · brokerage |
| Ratio and proportion | ☐ simplify a ratio · solve a:b = c:d · direct/inverse proportion · divide in a ratio · compound ratio · partnership shares |
| Mixtures | ☐ alligation · mean price · repeated replacement (1 − r/V)ⁿ |
| Averages | ☐ arithmetic, weighted, geometric, harmonic and quadratic (RMS) mean · average of two speeds 2ab/(a + b) |
| Moving averages | ☐ simple, weighted and exponential moving average · running average |
| Rates, time and work | ☐ d = s·t · relative speed · streams (b ± s) · combined work 1/(1/a + 1/b) · pipes and cisterns |
| Calendar and clock | ☐ leap year · day of the week (Zeller) · days between dates · clock-hand angle \|30h − 5.5m\| |
| Rounding for people | ☐ round to n decimal places · round to n significant figures · scientific/engineering notation · percent error · approximation and estimation |

### B. Number basics and number theory

| Group | Formulas |
|---|---|
| HCF/LCM | ✅ two numbers · ☐ a whole list · ☐ of fractions |
| Divisibility | ☐ divisor list · divisor count τ(n) · divisor sum σ(n) · perfect, abundant and deficient numbers · amicable pairs |
| Primes | ✅ primality test, next prime · ☐ sieve of Eratosthenes · prime factorization (trial division + Pollard rho) · prime counting · nth prime · twin primes |
| Arithmetic functions | ☐ Euler totient φ(n) · Möbius μ(n) · Carmichael λ(n) · radical rad(n) · Liouville λ(n) |
| Modular arithmetic | ✅ mulmod, powmod, modinv · ☐ Chinese remainder theorem · discrete log (baby-step giant-step) · Legendre/Jacobi symbol · modular square root (Tonelli–Shanks) · primitive root |
| Integer sequences | ☐ Fibonacci and Lucas (fast doubling) · Catalan · Bell · Stirling numbers (both kinds) · partitions p(n) · triangular, square, pentagonal numbers |
| Diophantine equations | ☐ linear ax + by = c (all solutions) · Pell's equation x² − Dy² = 1 · Pythagorean triple generation · sums of two squares |
| Special numbers | ☐ perfect powers and integer nth root · Mersenne prime test (Lucas–Lehmer) · Fermat/Carmichael checks · Egyptian fractions |
| Digits and bases | ☐ digit sum, digital root · reverse · palindrome · digit count · Armstrong numbers · base conversion (2–36) · Roman numerals |
| Integer arithmetic | ☐ floor/ceil division · divmod · positive modulo · saturating and overflow-checked add/sub/mul · overflow-free average · i32 versions |
| Fractions | ☐ normalize · add, subtract, multiply, divide · compare · fraction ↔ decimal · continued fractions · best rational approximation |
| Fixed point | ☐ Q15, Q31, Q16.16, Q32.32: convert, add, multiply, divide, sqrt, sin/cos, saturation |
| Big integers | ☐ arbitrary size: add, subtract, multiply (Karatsuba), divide, powmod, gcd, decimal string conversion |

### C. Algebra

| Group | Formulas |
|---|---|
| Equations | ☐ linear · quadratic (stable formula, discriminant) · cubic (Cardano / trigonometric) · quartic (Ferrari) · 2×2 and 3×3 systems (Cramer) |
| Polynomials | ✅ evaluate · ☐ add, multiply, divide with remainder · derivative, integral · roots of any degree (Durand–Kerner, Jenkins–Traub) · GCD · interpolation through points · Chebyshev, Legendre, Hermite, Laguerre polynomials |
| Progressions | ☐ arithmetic: nth term a + (n−1)d, sum n/2·(2a + (n−1)d) · geometric: nth term arⁿ⁻¹, sum a(rⁿ − 1)/(r − 1), infinite sum a/(1 − r) · harmonic progression · AM–GM–HM |
| Series | ☐ Σn, Σn², Σn³, Σkᵖ (Faulhaber) · arithmetico-geometric series · binomial expansion terms |
| Exponents and logs | ✅ powers, logs in base e/2/10 · ☐ log in any base · integer power of a float (powi) · logaddexp of two values |
| Rational functions | ☐ evaluate p(x)/q(x) · partial fractions · polynomial composition · resultant and discriminant of any degree |
| Solving | ☐ exponential and logarithmic equations · absolute-value and floor/ceil equations · nonlinear systems by Newton (see G) |

### D. Geometry and mensuration

| Group | Formulas |
|---|---|
| 2D shapes | ☐ area and perimeter: square, rectangle, parallelogram, rhombus, trapezium, kite, triangle (½bh, Heron, ½ab·sin C), regular n-gon, circle, sector, segment, annulus, ellipse (Ramanujan perimeter) |
| Triangle | ☐ sine rule · cosine rule · inradius A/s · circumradius abc/4A · medians, altitudes, angle bisectors · centroid, incenter, circumcenter, orthocenter · Pythagorean triples |
| Circle | ☐ chord · arc length · tangent length · circle through 3 points · circle–circle intersection |
| 3D solids | ☐ volume and surface area: cube, cuboid, cylinder, cone, frustum, sphere, hemisphere, spherical cap, prism, pyramid, torus, ellipsoid |
| Coordinate geometry | ☐ distance · midpoint · section formula · slope · line equations · angle between lines · point–line distance · line intersection · collinearity · polygon area (shoelace) · point in polygon · convex hull |
| Conics | ☐ circle, parabola, ellipse, hyperbola: standard forms, foci, eccentricity |
| 3D coordinates | ☐ distance · plane through 3 points · line–plane intersection · point–plane distance · angle between planes |
| Computational geometry | ✅ 2D affine, Bézier, arcs · ☐ segment intersection · closest pair · polygon clipping · triangulation · bounding boxes · ray–box/sphere/triangle intersection |
| Spatial tests | ☐ barycentric coordinates · triangle–triangle and box–box tests · plane and frustum tests · bounding spheres · signed distance functions (circle, box, capsule, …) |
| Meshes and diagrams | ☐ Delaunay triangulation · Voronoi diagram · polygon offset and union · mesh area, volume and normals |
| Curves and surfaces | ☐ B-splines · NURBS · Catmull–Rom splines · Hermite curves · curve arc length and reparameterization · Bézier fitting to points · bicubic patches |
| Animation curves | ☐ lerp, inverse lerp, remap · smoothstep, smootherstep · easing functions (quad, cubic, sine, expo, elastic, bounce, back) · spring/damping curves |

### E. Trigonometry, extended

| Group | Formulas |
|---|---|
| Functions | ✅ sin … atanh · ☐ sincos · sinpi, cospi, tanpi · sec, csc, cot and their inverses and hyperbolic forms · versine, haversine |
| More functions | ☐ sinc · Gudermannian · arcsec, arccsc, arccot (and hyperbolic) · exsecant, excosecant |
| Angles | ☐ degrees ↔ radians ↔ gradians · normalize to [0, 2π) or (−π, π] · smallest angle difference |
| Spherical | ☐ great-circle (haversine) distance · initial bearing · spherical law of cosines |

---

## Stage 2

### F. Linear algebra

| Group | Formulas |
|---|---|
| Vectors (2, 3, 4, n) | ☐ add, subtract, scale · dot, cross, triple product · length, normalize, distance · lerp · project, reflect · angle between |
| Matrices (2×2, 3×3, 4×4) | ☐ multiply, transpose, determinant, inverse, trace, identity · translate, scale, rotate · look-at, perspective, orthographic |
| Quaternions | ☐ multiply, conjugate, inverse · axis-angle and matrix conversions · rotate a vector · slerp |
| General n×n | ☐ LU, QR and Cholesky · solve Ax = b · determinant · inverse · rank · least squares |
| Eigenvalues | ☐ power iteration · Jacobi (symmetric) · QR algorithm · SVD |
| BLAS-style | ☐ axpy · gemv · gemm (`gemm/`) · L1, L2, ∞ and Frobenius norms |
| Rotations | ☐ Euler angles ↔ matrix ↔ quaternion · axis-angle · rotation between two vectors · dual quaternions (rotation + translation) · transform decomposition (translate/rotate/scale) |
| More matrix algebra | ☐ Gram–Schmidt · Householder reflections · pseudo-inverse · condition number · matrix exponential · Kronecker product · matrix power |
| Sparse and tensors | ☐ sparse matrices (CSR/CSC): multiply, solve · n-dimensional arrays: reshape, transpose, broadcast, slicing, reductions along an axis |

### I. Complex numbers

| Group | Formulas |
|---|---|
| Arithmetic | ☐ add, subtract, multiply, divide (overflow-safe) · conjugate · abs · argument · polar ↔ rectangular |
| Functions | ☐ exp, log, pow, sqrt · sin, cos, tan, their inverses and hyperbolic forms |
| Roots | ☐ nth roots of unity · de Moivre |
| Dual numbers | ☐ a + bε arithmetic and elementary functions: exact first derivatives (automatic differentiation) |

### H. Statistics and probability

| Group | Formulas |
|---|---|
| Basic | ✅ sum, mean, running mean/variance, logsumexp |
| Descriptive | ☐ variance and standard deviation (population, sample) · median · mode · range · quartiles, percentiles, IQR · mean absolute deviation · skewness · kurtosis · z-score · coefficient of variation |
| Relationships | ☐ covariance · Pearson and Spearman correlation · linear regression (slope, intercept, R²) · polynomial regression |
| Grouped data | ☐ histogram · frequency and cumulative frequency tables · grouped mean, median, mode |
| Probability | ✅ nCr · ☐ nPr · with/without repetition · conditional probability · Bayes |
| Distributions | ☐ uniform, normal, binomial, Poisson, exponential, geometric, gamma, beta, chi-square, Student t, F: PDF, CDF, inverse CDF, sampling |
| Inference | ☐ z-test · t-test · chi-square test · confidence intervals |
| More tests | ☐ ANOVA · Mann–Whitney U · Kolmogorov–Smirnov · Wilcoxon signed-rank · bootstrap confidence intervals |
| Data preparation | ☐ min-max and z-score normalization · outlier detection (IQR, z-score) · ranking · weighted variance · kernel density estimate |
| Time series | ☐ autocorrelation · differencing · exponential smoothing (Holt–Winters) · trend fitting |
| Markov chains | ☐ transition matrices · stationary distribution · absorbing chains · random walks |
| Random | ✅ uniform reals · ☐ normal (Box–Muller / Ziggurat) · exponential · unbiased integer in a range · shuffle · sampling |
| Low-discrepancy and noise | ☐ Halton and Sobol sequences · random points in a disk, on a sphere, in a triangle · Perlin and simplex noise · Poisson-disk sampling |

### K. Discrete math and combinatorics

| Group | Formulas |
|---|---|
| Counting | ✅ combinations · ☐ permutations nPr · multisets · derangements !n · arrangements with repetition |
| Generation | ☐ next permutation · next combination · Gray code · power set · integer partitions |
| Sets and logic | ☐ bitset union, intersection, difference, symmetric difference · truth tables |
| Graphs | ☐ shortest paths (Dijkstra) · minimum spanning tree · topological order |
| More graph algorithms | ☐ BFS/DFS · connected components · Floyd–Warshall · Bellman–Ford · maximum flow · bipartite matching · graph coloring (greedy) |
| Boolean algebra | ☐ Karnaugh maps / Quine–McCluskey minimization · normal forms (CNF/DNF) |
| Recurrences | ☐ linear recurrences by matrix power · Josephus problem · Collatz length |

### O. Abstract algebra

| Group | Formulas |
|---|---|
| Finite fields | ☐ GF(p) arithmetic (on top of modular arithmetic) · GF(2ⁿ) multiply, inverse, power (e.g. GF(2⁸) with log tables and carry-less multiply) |
| Polynomials over fields | ☐ add, multiply, divide, GCD, evaluation over GF(p) and GF(2ⁿ) · irreducibility test |
| Groups | ☐ permutations as group elements: compose, inverse, order, cycle decomposition, sign |
| Elliptic curves | ☐ point add and double · scalar multiplication · on short Weierstrass and Montgomery curves over GF(p) (the math under modern public-key cryptography) |

### P. Information theory and coding

| Group | Formulas |
|---|---|
| Information measures | ☐ entropy H = −Σ p log p · joint and conditional entropy · KL divergence · cross-entropy · mutual information · Jensen–Shannon divergence |
| Distances | ☐ Hamming · Levenshtein (edit) · Jaccard · cosine similarity · Manhattan, Euclidean, Chebyshev, Minkowski |
| Error-correcting codes | ☐ parity · Hamming(7,4) and SECDED · CRC as polynomial division over GF(2) · Reed–Solomon encode/decode (on GF(2⁸)) |

---

## Stage 3

### G. Calculus and numerical methods

| Group | Formulas |
|---|---|
| Root finding | ☐ bisection · Newton–Raphson · secant · Brent |
| Differentiation | ☐ forward, backward, central differences · Richardson extrapolation |
| Integration | ☐ trapezoidal · Simpson 1/3 and 3/8 · Romberg · Gauss–Legendre · adaptive quadrature |
| More integration | ☐ Monte Carlo integration · double and triple integrals · improper integrals (infinite ranges, endpoint singularities) |
| Interpolation | ☐ linear, bilinear · Lagrange · Newton divided differences · cubic spline · Hermite |
| Differential equations | ☐ Euler · Heun · Runge–Kutta 4 · adaptive RK45 |
| Stiff and boundary problems | ☐ implicit Euler · backward differentiation (BDF) · shooting method · finite differences for simple PDEs (heat, wave, Laplace) |
| Optimization | ☐ golden-section search · gradient descent · Nelder–Mead |
| More optimization | ☐ Newton's method · BFGS / L-BFGS · conjugate gradient · Levenberg–Marquardt (nonlinear least squares) · linear programming (simplex) |
| Series | ☐ Taylor series evaluation · Aitken acceleration |
| Continued fractions and sums | ☐ continued fraction evaluation (Lentz) · Euler–Maclaurin summation · Padé approximants |
| Transforms | ☐ FFT/IFFT · DCT · convolution · correlation |

### J. Special functions, extended

| Group | Formulas |
|---|---|
| Gamma family | ✅ Γ, ln Γ, erf, erfc · ☐ beta B(a, b) · digamma ψ · polygamma · incomplete gamma P, Q · incomplete beta · inverse erf |
| Integral functions | ☐ sine and cosine integrals Si, Ci · exponential integrals Ei, E₁ · Fresnel S, C · logarithmic integral li |
| Others | ☐ Bessel J₀, J₁, Jₙ, Y₀, Y₁, Yₙ, modified I, K · Airy · Riemann zeta · Lambert W · elliptic integrals K, E |
| Hypergeometric and orthogonal | ☐ hypergeometric ₁F₁, ₂F₁ · Legendre functions · spherical harmonics · Pochhammer symbol · binomial coefficient for real arguments · logistic and logit |

---

## Stage 4

### M. Machine learning

| Group | Formulas |
|---|---|
| Activations | ☐ sigmoid · tanh · ReLU, leaky ReLU · ELU · GELU · SiLU/swish · softplus · softmax, log-softmax |
| Normalization | ☐ layer norm · batch norm · RMS norm |
| Losses | ☐ MSE · MAE · cross-entropy · Huber |
| Core | ☐ GEMM · convolution · attention · int8/int4 quantization (via `dtype/`) |

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*
