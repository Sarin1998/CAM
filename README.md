The original version while trying to install CESM 2.2.2 runs into the error of it using SVN which is not supported anymore instead of git. I have just changed the Externals_CAMS.cfg file here and then linked it to the Externals.cfg file in the original CESM model bundle. The model runs properly now!!



# CAM: The Community Atmosphere Model

## NOTE: This is **unsupported** development code and is subject to the [CESM developer's agreement](http://www.cgd.ucar.edu/cseg/development-code.html).

### CAM Documentation - https://ncar.github.io/CAM/doc/build/html/index.html

### CAM6 namelist settings - http://www.cesm.ucar.edu/models/cesm2/settings/current/cam_nml.html

Please see the [wiki](https://github.com/ESCOMP/CAM/wiki) for complete documentation on CAM, getting started with git and how to contribute to CAM's development.
