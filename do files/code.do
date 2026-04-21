* Ghana Socioeconomic Study 
* Auther: Yuki Chen
* Date: 2025/9/28
* This is an independent exploratory study working with the Ghana Socioeconomic Panel Survey from Yale Economic Growth Center, a dataset that tracks the living standards of individuals in Ghana over time.

* Set working directory
cd "/Users/YUKIchen/Downloads/DIME RA Application_Yiqing_Yuki_CHEN/Stata"
global Raw = "02_Data/Raw Data"
global Output = "03_Figures"

log using $Output/logfile, replace 
clear
set more off

* Input Data: Household locations
frame create ghh
frame change ghh
import delimited "02_Data/Raw Data/Ghana_household_locations.csv", varnames(1) clear
save "02_Data/Working Data/ghh_raw.dta", replace

* Input Data: Wave 1 consumption
frame create w1
frame change w1
import delimited "02_Data/Raw Data/hh_consumption_w1.csv", varnames(1) clear
save "02_Data/Working Data/w1_raw.dta", replace

* Input Data: Wave 2 consumption
frame create w2
frame change w2
import delimited "02_Data/Raw Data/hh_consumption_w2.csv", varnames(1) clear
save "02_Data/Working Data/w2_raw.dta", replace

* Input Data: Wave 3 consumption
frame create w3
frame change w3
import delimited "02_Data/Raw Data/hh_consumption_w3.csv", varnames(1) clear
save "02_Data/Working Data/w3_raw.dta", replace

***********************
* Data Quality Checks *
***********************

* 1. Check file structure, variable names
frame dir   
local frames ghh w1 w2 w3
foreach f of local frames {
    di "===== Frame: `f' ====="
    frame change `f'
    describe
    ds
}
// fprimary exists in all datasets

* 2. Verify uniqueness of fprimary in the three datasets
foreach f in ghh w1 w2 w3 {
    frame change `f'
    isid fprimary
    duplicates report fprimary
}
// No surplus duplicates were found. fprimary is a unique identifier in each frame. 

* 3. Check missingness
foreach f in ghh w1 w2 w3 {
    frame change `f'
    misstable summarize
}
// No missingness in ghh, w2, and w3.
// In w1, total_cons2009 has 9 missing values among 5009 observations. Consider missing values as minor influence.

* 4. Check consumption ranges
foreach f in w1 w2 w3 {
    frame change `f'
    summarize total_cons*
    summarize total_cons*, detail
    graph box total_cons*, ///
	title("Consumption Distribution in `f'") ///
	ytitle("Household Consumption (USD)")
	
	graph export "03_Figures/box_cons_range_`f'.png", replace
}
// Checked - no negative value.
// Medium and mean both rise across waves.  

* 5. Cross-check attrition (whether all IDs from ghh exist in w1, w2, w3)
frame change ghh
local waves w1 w2 w3

foreach w of local waves {
    di "===== Linking ghh with `w' ====="
    frlink 1:1 fprimary, frame(`w')
    count if missing(`w')
}
// The number of drop out in w1: 1328; w2: 1563; w3: 668. The attrition looks normal - doesn't impact this study.
drop w1 w2 w3

* 6. Cross-check whether all IDs from w1, w2, w3 exist in ghh
local waves w1 w2 w3
foreach w of local waves {
    di "===== Checking coverage: `w' IDs in ghh ====="
    frame change `w'
	frlink m:1 fprimary, frame(ghh)
    count if missing(ghh)
}
// All IDs from w1, w2, w3 exist in ghh

** Drop "ghh" in w1 w2 w3
local waves w1 w2 w3
foreach w of local waves {
    frame change `w'
    capture drop ghh   
}

********************************
* Data Cleaning & Construction *
********************************

* 1. Merge w1, w2, and w3 with ghh, saved in a new frame "master"
frame create master
frame change master
use "02_Data/Working Data/ghh_raw.dta", clear

frlink 1:1 fprimary, frame(w1)
frget *, from(w1)

frlink 1:1 fprimary, frame(w2)
frget *, from(w2)

frlink 1:1 fprimary, frame(w3)
frget *, from(w3)

drop w1 w2 w3

save "02_Data/Working Data/ghh_merged.dta", replace

* 2. Reshape ghh_merged: create a survey year as a column, combine total_cons2009, total_cons2013, total_cons2018 into a single column "consumption"
reshape long total_cons, i(fprimary) j(year)
rename total_cons consumption

* 3. Transfer "consumption" variable from Ghana Cedis to USD
** Step1: Import a file of PPP conversion factor 
frame create ppp
frame change ppp
import delimited "02_Data/Raw Data/API_PA.NUS.PPP_DS2_en_csv_v2_4696496.csv", rowrange(5) varnames(5) clear
save "02_Data/Working Data/ppp.dta", replace

** Step2: Create a tibble of Ghana Cedid - USD conversation rates across years
frame change ppp
keep if countryname == "Ghana"
reshape long v, i(countryname) j(year)
replace year = year + 1955
rename v usd_ppp_exchange
keep year usd_ppp_exchange

** Step3: join ppp with ghh
frame change master
frlink m:1 year, frame(ppp)
frget usd_ppp_exchange, from(ppp)
drop ppp

** Step4: create a variable "consumption_usd" equal to consumption in US dollars, PPP terms
gen consumption_usd = consumption * usd_ppp_exchange

* 4. Considering inflation, convert consumption_usd to 2021 US Dollars
** Input cpi data
frame create cpi
frame change cpi
import excel "02_Data/Raw Data/us_consumer_price_index.xlsx", firstrow clear
save "02_Data/Working Data/cpi.dta", replace 

** Merge cpi data with ghh_merged
frame change master
frlink m:1 year, frame(cpi)
frget cpi_conversion, from(cpi)
drop cpi

** Calculate 2021 USD
gen consumption_usd_2021 = consumption_usd * (1/cpi_conversion)

****************
* Data Analysis*
****************

* 1. Plot the distribution of consumption_usd_2021 by wave (year)
graph box consumption_usd_2021, over(year) ///
    title("Distribution of Household Consumption (2021 USD)") ///
    ytitle("Consumption (2021 USD)")
graph export "03_Figures/box_consumption_by_wave.png", replace

* 2. Plot distribution of consumption growth, by region of the country, between 2009 and 2013.

** Step1: For each household, create a lagged value of consumption (ie consumption for that household in the previous survey wave). I know from previous analysis that some households are not in every wave; this won't affect this study. I will let stata determine what gets converted to NA) 
frame change master
sort fprimary year
xtset fprimary year, delta(4)
gen lag_consumption_usd_2021 = L.consumption_usd_2021
*** Create a new variable, equal to change in consumption between the current wave and previous wave
gen change_consump_usd_2021 = consumption_usd_2021 - lag_consumption_usd_2021

** Step2: Create a box plot of consumption growth, by region of the country, between 2009 and 2013
encode region, gen(region_id)
preserve
graph box change_consump_usd_2021, over(region_id) horizontal title("Change in Consumption (2009 to 2013)")
graph export "03_Figures/box_consumption_growth_by_region.png", replace

 
* 3. Calcute means of consumption_usd_2021 of each region and year (2019, 2013, 2018)
frame change master

levelsof region, local(regions)

* Open postfile
tempname results
postfile `results' str30 region year mean using "02_Data/Working Data/cons_region_stats.dta", replace

* Loop through years and regions
foreach yr in 2009 2013 2018 {
    foreach r of local regions {
        quietly summarize consumption_usd_2021 if year==`yr' & region==`"`r'"'
        local m = r(mean)
        if !missing(`m') {
            post `results' ("`r'") (`yr') (`m')
        }
    }
}

postclose `results'


frame create stats2
frame change stats2
use "02_Data/Working Data/cons_region_stats.dta", clear
list


* 4. Create a histogram of mean household consumption (USD 2021) of Ghana's capital (Greater Accra) across survey years (2019, 2013, 2018)
frame change stats2
preserve
keep if region == "Greater Accra Region"
twoway (bar mean year,) ///
    (line mean year, lwidth(medium) lcolor(maroon) msymbol(circle)), ///
	title("Average Household Consumption Across Survey Years ") ///
    subtitle("Greater Accra Region") ///
    ytitle("Household Consumption (2021 USD)", size(small)) ///
    xtitle("Year") ///
	xlabel(2009 2013 2018) ///
	legend(off) ///
    name(bar_accra, replace)
graph export "03_Figures/bar_mean_consumption_accra.png", name(bar_accra) replace
restore

* 5. Do poorer households (low baseline consumption) experience higher/lower consumption growth? 
** Y: change_consump_usd_2021, X: lag_consumption_usd_2021
** Restrict to years where lag is defined (2013 & 2018)
frame change master
keep if inlist(year, 2013, 2018)
reg change_consump_usd_2021 lag_consumption_usd_2021, vce(cluster region)

twoway (scatter change_consump_usd_2021 lag_consumption_usd_2021, msymbol(o) msize(vsmall) mcolor(gs10)) ///
       (lfit change_consump_usd_2021 lag_consumption_usd_2021), ///
       title("Regression: Baseline vs Growth in Consumption") ///
       ytitle("Change in Consumption (2021 USD)") ///
       xtitle("Lagged Consumption (2021 USD)") ///

graph export "03_Figures/reg_change_on_lagcons_scatterfit_2013_2018.png", replace
// Most households cluster at low baseline consumption (< 500 USD), with wide variation in growth.
// Slight upward slope - households with higher baseline consumption tend to have higher absolute growth, but the effect is not strong (p-value is not significant).
