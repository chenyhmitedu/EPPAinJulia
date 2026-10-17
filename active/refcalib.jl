"""
Reference calibration. GDP stays on the exogenous path and `gprod` adjusts.
`simu = 1` would take productivity as given; that run is not the TFP calibration.
"""

set_model_years!([2017; 2020:5:2100])
simu = 0
