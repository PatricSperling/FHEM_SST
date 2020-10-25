# SST - Samsung SmartThings Module for FHEM

This module connects to the Samsung SmartThings cloud service and detects its devices. These Devices can then be auto-added to FHEM (https://fhem.de).
The single devices can then be managed via FHEM.

Attention: This module is still under development. Please report any issues (https://forum.fhem.de/index.php/topic,113820.0.html).

## Installation

In FHEM run:
```
update add https://raw.githubusercontent.com/PatricSperling/FHEM_SST/master/controls_SST.txt
update all
update
shutdown restart
```

The further proceedings can then be taken from the inline documentation.

## License

MIT License

Copyright (c) 2020 Patric Sperling

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
