
function solve_IP(nteams,nweeks,win_matrix,returntype)
   multi = Model(HiGHS.Optimizer)
   set_optimizer_attribute(multi, "log_to_console", "false")

   # VARIABLES
   @variable(multi, pick[1:nteams,1:nweeks],Bin)
   # OBJECTIVE
   @objective(
      multi,
      Max,
      sum(
          win_matrix[i,w] * pick[i,w] for i = 1:nteams, w = 1:nweeks
      )
   )
   # CONSTRAINTS
   # pick a team at most once
   @constraint(
      multi,
      atmostonce[i=1:nteams],
      sum(pick[i, p] for p in 1:nweeks) <= 1
   )

   #pick a single team per week
   @constraint(
      multi,
      singleteam[w=1:nweeks],
      sum(pick[i, w] for i in 1:nteams) == 1
   )

   optimize!(multi)
   if returntype == 1
      sol =  JuMP.value.(pick[:,1]);
   else
      sol =  JuMP.value.(pick[:,:]);
   end
   return sol
end

function compute_win_prob(elo_diff)
   return 1/(10^(-(elo_diff)/400)+1);
end
