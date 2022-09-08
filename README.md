# nfl_survivor_optimize

## Optimize Survivor Picks

Use ELO from 538 and optimization to figure out how to win!

Reference: Bergman and Imbrogno (2017), https://pubsonline.informs.org/doi/10.1287/opre.2017.1633

### nfl_pred_2022.jl
For current season, set current_week, forward_length, and history_of_picks to generate an optimal choice of teams in the next forward_length weeks 

Let $x_{w,t}$ denote a binary variable for whether team $t$ is picked in week $w$. The optimization problem is to start in current week $w'$ and look ahead $L$ periods (corresponding to forward_length)
$$\max_{x_{w,t} \in \{0,1\}} \sum_{w=w'}^{w'+L-1} \sum_{t \in T_{w'}} x_{w,t} \log p_{w',w',t} $$
$$\text{subject to} \quad \sum_{w} x_{w,t} \leq 1, \forall t \in T_{w'}, \quad  \sum_{t} x_{w,t} = ,  \forall w \in w',...,w'+L-1$$
where $T_{w'}$ denotes the set of remaining/unpicked teams and $p_{w',w,t}$ denotes the predicted win chance of team $t$ in week $w$ with information at current week $w'$. $p_{w',w,t}$ is obtained from 538 ELO predictions.

Notice that $L=1$ corresponds to a greedy algorithm where the team with the highest win probability for the current week is picked. The history_of_picks variable should be a list of strings that correspond to the team names used in the 538 CSV file.

### nfl_analysis.jl
How do we determine $L$? I first consider a case where we choose a constant $L$ in each week. Similar to Bergman and Imbrogno (2017), I find that a greedy algorithm or a 8-week algorithm performs best.



