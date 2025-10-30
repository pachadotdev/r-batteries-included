# R 4.5.1 - Batteries Included

R Batteries Included detects your CPU cores and configures itself for maximum performance. I created this to assist some lab colleagues who were struggling with the R setup on their Windows machines.

The installer includes OpenBLAS for faster linear algebra operations and the components required to install packages from source (e.g., from GitHub).

Your existing code works exactly the same, just faster, and does not requires changes to existing workflows.

Whether you're analyzing large datasets, running simulations, or building statistical models, this is the easiest performance upgrade you'll ever make.

Download link:

https://github.com/pachadotdev/r-batteries-included/releases/download/4.5.1/R-4.5.1-Batteries-Included.exe

Optional donation for the time to create and test the installer:

[![BuyMeACoffee](https://raw.githubusercontent.com/pachadotdev/buymeacoffee-badges/main/bmc-blue.svg)](https://buymeacoffee.com/pacha/e/414420)

If you install vanilla R and try to install a package with compiled code (e.g., a package with C++ code from GitHub), you may see errors like this:

```r
> remotes::install_github("pachadotdev/kendallknight")

In missing_devel_warning(pkgdir) :
  Package kendallknight has compiled code, but no suitable compiler(s) were found. Installation will likely fail.
  Install Rtools (https://cran.r-project.org/bin/windows/Rtools/).Then use the pkgbuild package, or make sure that Rtools in the PATH.
```

With R Batteries Included, the installation works out of the box:

```r
> remotes::install_github("pachadotdev/kendallknight")

Installing package into C:/Users/vboxuser/AppData/Local/R/win-library/4.5
(as lib is unspecified)
cpp4r/include'   -I"c:/rtools45/x86_64-w64-mingw32.static.posix/include"   -fopenmp   -O2 -Wall  -mfpmath=sse -msse2 -mstackrealign    -c cpp4r.cpp -o cpp4r.o
g++ -std=gnu++17  -I"C:/R/R-45~1.1/include" -DNDEBUG  -I'C:/Users/vboxuser/AppData/Local/R/win-library/4.5/cpp4r/include'   -I"c:/rtools45/x86_64-w64-mingw32.static.posix/include"   -fopenmp   -O2 -Wall  -mfpmath=sse -msse2 -mstackrealign    -c kendall_correlation.cpp -o kendall_correlation.o
g++ -std=gnu++17 -shared -s -static-libgcc -o kendallknight.dll tmp.def cpp4r.o kendall_correlation.o -fopenmp -Lc:/rtools45/x86_64-w64-mingw32.static.posix/lib/x64 -Lc:/rtools45/x86_64-w64-mingw32.static.posix/lib -LC:/R/R-45~1.1/bin/x64 -lR
* DONE (kendallknight)
```

The default installation path is `C:\R`. You can remove other R installations to avoid confusion, but it's not required.

Works with RStudio and Visual Studio Code.
