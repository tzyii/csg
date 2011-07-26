#! /bin/bash -e
#
# Copyright 2009 The VOTCA Development Team (http://www.votca.org)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

if [ "$1" = "--help" ]; then
cat <<EOF
${0##*/}, version %version%
This script implemtents the function prepare for the PMF calculator

Usage: ${0##*/}

EOF
  exit 0
fi

conf_start="conf_start"
min=$(csg_get_property cg.non-bonded.pmf.min)
max=$(csg_get_property cg.non-bonded.pmf.max)
mdp_prep=$(csg_get_property cg.non-bonded.pmf.mdp_prep)
mdp_opts="$(csg_get_property --allow-empty cg.inverse.gromacs.grompp.opts)"

cp_from_main_dir $mdp_prep
mv $mdp_prep grompp.mdp

pullgroup0=$(get_simulation_setting pull_group0)
pullgroup1=$(get_simulation_setting pull_group1)
rate=$(get_simulation_setting pull_rate1)
steps=$(get_simulation_setting nsteps)
dt=$(get_simulation_setting dt)

# Generate tpr file
grompp -n index.ndx -c conf.gro -o topol.tpr -f grompp.mdp -po ${mdp_prep} ${mdp_opts}

# Calculate distance
echo -e "${pullgroup0}\n${pullgroup1}" | g_dist -f conf.gro -s topol.tpr -n index.ndx -o ${conf_start}.xvg
dist=$(sed '/^[#@]/d' ${conf_start}.xvg | awk '{print $2}')
[ -z "$dist" ] && die "${0##*/}: Could not fetch dist"
echo Found distance $dist

# Calculate number of simulations to be done
steps="$(awk "BEGIN{print int(($max-$dist)/$rate/$dt)}")"
# Determine whether to pull apart or together
if [ $steps -le 0 ]; then
  steps="${steps#-}"
  rate="-$rate"
fi
((steps++))
sed -i -e "s/nsteps.*$/nsteps                   = $steps/" \
         -e "s/pull_rate1.*$/pull_rate1               = $rate/" \
         -e "s/pull_init1.*$/pull_init1               = $dist/" grompp.mdp
  
msg Doing $(($steps+1)) simulations with rate $rate

# Run simulation
grompp -n ${index} ${mdp_opts}
do_external run gromacs

# Wait for job to finish when running in background
confout="$(csg_get_property cg.inverse.gromacs.conf_out "confout.gro")"
background=$(csg_get_property --allow-empty cg.inverse.simulation.background "no")
sleep_time=$(csg_get_property --allow-empty cg.inverse.simulation.sleep_time "60")
sleep 10
if [ "$background" == "yes" ]; then
  while [ ! -f "$confout" ]; do
    sleep $sleep_time
  done
else
  [ -f "$confout" ] || die "${0##*/}: Gromacs final coordinate file '$confout' not found after mdrun"
fi

# Calculate new distance and chop up trajectory
echo -e "${pullgroup0}\n${pullgroup1}" | g_dist -n index.ndx
echo "System" | trjconv -sep -o ${conf_start}.gro