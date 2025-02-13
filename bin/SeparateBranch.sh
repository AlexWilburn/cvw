#!/bin/bash

###########################################
## Written: ross1728@gmail.com
## Created: 12 March 2023
## Modified: 
##
## Purpose: Converts a single branch.log containing multiple benchmark branch outcomes into
##          separate files, one for each program.x4
##
## A component of the CORE-V-WALLY configurable RISC-V project.
##
## Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
##
## SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
##
## Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file 
## except in compliance with the License, or, at your option, the Apache License version 2.0. You 
## may obtain a copy of the License at
##
## https:##solderpad.org/licenses/SHL-2.1/
##
## Unless required by applicable law or agreed to in writing, any work distributed under the 
## License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
## either express or implied. See the License for the specific language governing permissions 
## and limitations under the License.
################################################################################################

File="$1"
TrainLineNumbers=`cat $File | grep -n "TRAIN" | awk -NF ':' '{print $1}'`
BeginLineNumbers=`cat $File | grep -n "BEGIN" | awk -NF ':' '{print $1}'`
Name=`cat $File | grep -n "BEGIN" | awk -NF '/' '{print $6_$4}'`
EndLineNumbers=`cat $File | grep -n "END" | awk -NF ':' '{print $1}'`
echo $Name
echo $BeginLineNumbers
echo $EndLineNumbers

NameArray=($Name)
TrainLineNumberArray=($TrainLineNumbers)
BeginLineNumberArray=($BeginLineNumbers)
EndLineNumberArray=($EndLineNumbers)

mkdir -p branch
Length=${#EndLineNumberArray[@]}
for i in $(seq 0 1 $((Length-1)))
do
    CurrName=${NameArray[$i]}
    CurrTrain=$((${TrainLineNumberArray[$i]}+1))
    CurrEnd=$((${EndLineNumberArray[$i]}-1))
    echo $CurrName, $CurrTrain, $CurrEnd
    sed -n "${CurrTrain},${CurrEnd}p" $File > branch/${CurrName}_branch.log
done
