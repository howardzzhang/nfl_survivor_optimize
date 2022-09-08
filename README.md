# nfl_survivor_optimize

## Optimize Survivor Picks

Use ELO from 538 and optimization to figure out how to win! A NFL survivor pool entails decisions over (high-dimensional) trade-offs and a tremendous amount of randomness. Should we pick a strong team today because they have a difficult schedule ahead? Or a weaker team today because another strong team has an easy schedule ahead?

Reference: Bergman and Imbrogno (2017), https://pubsonline.informs.org/doi/10.1287/opre.2017.1633

### nfl_pred_2022.jl
For current season, set current_week, forward_length, and history_of_picks to generate an optimal choice of teams in the next forward_length weeks 

Let $x_{w,t}$ denote a binary variable for whether team $t$ is picked in week $w$. The optimization problem is to start in current week $w'$ and look forward $L$ periods (corresponding to forward_length)
$$\max_{x_{w,t} \in \{0,1\}} \sum_{w=w'}^{w'+L-1} \sum_{t \in T_{w'}} x_{w,t} \log p_{w',w,t} $$
$$\text{subject to} \quad \sum_{w} x_{w,t} \leq 1, \forall t \in T_{w'}, \quad  \sum_{t} x_{w,t} = ,  \forall w \in w',...,w'+L-1$$
where $T_{w'}$ denotes the set of remaining/unpicked teams and $p_{w',w,t}$ denotes the predicted win chance of team $t$ in week $w$ with information at current week $w'$. $p_{w',w,t}$ is obtained from 538 ELO predictions. Crucially, note that $p_{w,w,t}$ is unobserved at time $w'$ for $w' < w$. This optimization problem is easily solved using any IP solver.

Notice that $L=1$ corresponds to a greedy algorithm where the team with the highest win probability for the current week is picked. The history_of_picks variable should be a list of strings that correspond to the team names used in the 538 CSV file.

Packages used: JuMP with HiGHS

### nfl_analysis.jl
How do we determine the optimal look forward periods $L$? Using historical data from 1990-2021 seasons (skipping 2020 Covid), I first consider a case where we choose a constant $L$ in each week. Similar to Bergman and Imbrogno (2017), I find that a 8-week algorithm performs best in terms of log-likelihood, but behaves similar to a greedy algorithm in terms of expected survival time. 

Each week, I run a $L$ period look forward optimization problem (defined above). I then extract the pick for the current week only. In the subsequent week, I drop the pick selected in the previous week, use updated elos, and then re-run the optimization problem with the same $L$ look forward period. Crucially, the probabilities that enter the optimization problem are formed based only on the ELO available before the start of the current week.

The log likelihood of a strategy is defined as
$$\sum_{w=w'}^{w' + L-1} \sum_{t \in T_{w'}} x_{w,t}^* \log p_{w,w,t}$$ 
In contrast to the optimization problem that is solved each week, the updated probabilities are used each week in the computation of the log likelihood. By this definition, the optimal strategy if one knew the full set of $p_{w,w,t}$ would be to run a 17 look forward period at week 1.

![constant_lookforward_loglikelihood](https://user-images.githubusercontent.com/57815640/189217027-1c3f2fb9-6dbd-4c26-a0fd-8513fd1d6186.png)

In reality, one does not care about the likelihoods after two deaths (i.e., incorrect guesses). I also consider an alternative optimization which is my preferred, of actual survival time (with two lives) rather than the sum of log likelihoods. As seen, the optimal value of 9 produces a similar expected survival time as a greedy algorithm.

![constant_lookforward_survivalperiod](https://user-images.githubusercontent.com/57815640/189217126-b559f83b-ee9e-4646-8c3b-5b5f228641ef.png)

How about a week-specific $L$? I use a genetic algorithm to determine $L_{w'}$, for $w'=1,..,W-1$ (notice that if you survive until the last week $W$, the only available look forward period is 1.

Packages used: Evolutionary.jl, JuMP with HiGHS

### Discussion
Predictions are only as good as ELO system; lots of underlying parameters that I rely on based on 538, including their update rate, home field advantage, and quarterback adjustment

Are predicted win probabilities $p_{w',w,t}$ correct? One would probably want to simulate the games and subsequent elo updates. It is unclear how 1) to generate score differences that matter for elo updates, 2) include these simulations in a optimization problem (e.g., would one take the average of $p_{w',w,t}$ over all simulations?)


