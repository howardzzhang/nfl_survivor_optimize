using JuMP, DataFrames, CSV, Dates, Statistics, Random, HTTP
import HiGHS
include("util.jl")

#import latest season elo file from 538, estimate optimal choices given current week, history of picks, and projected length

function import_data()
   datafile="https://projects.fivethirtyeight.com/nfl-api/nfl_elo_latest.csv"
   dat = HTTP.get(datafile)
   alldata = CSV.read(dat.body, DataFrame)

   teams = unique(alldata.team1);
   sort!(teams)
   nteams = size(teams,1);

   alldata.dayofweek = dayofweek.(alldata.date);

   week_nfl = ones(size(alldata,1));
   for i = 2:size(alldata,1)
       if ((alldata.season[i] == alldata.season[i-1]) & (((alldata.dayofweek[i-1] < 3) & (alldata.dayofweek[i] >= 3)) | (alldata.date[i] -alldata.date[i-1]>=Dates.Day(6))))
          week_nfl[i] = week_nfl[i-1]+1;
       elseif (alldata.season[i] == alldata.season[i-1])
          week_nfl[i] = week_nfl[i-1];
       end
   end
   alldata.week = week_nfl;
   weeks = unique(alldata.week);
   nweeks = size(weeks,1);
   return (alldata, teams, nteams,weeks,nweeks)
end

function run_estimate(current_week, forward_length, history_of_picks,alldata, teams, nteams,weeks,nweeks)
   history_of_picks_enumerate = Int64[];
   for p = 1:size(history_of_picks,1)
      id = findfirst(history_of_picks[p].==teams)
      push!(history_of_picks_enumerate,id)
   end
   remaining_teams_vec = collect(1:nteams)

   l_p = crossjoin(DataFrame(teams=teams), DataFrame(week=weeks));
   l_p = leftjoin(l_p,alldata[:,[:team1,:week,:qbelo_prob1]],on=[:teams => :team1,:week])
   l_p = leftjoin(l_p,alldata[:,[:team2,:week,:qbelo_prob1]],on=[:teams => :team2,:week],makeunique=true)

   sort!(l_p,[:teams,:week])
   win_vec = ifelse.(ismissing.(l_p.qbelo_prob1) .& ismissing.(l_p.qbelo_prob1_1), 0, coalesce.(l_p.qbelo_prob1, 0) .+ coalesce.(1 .- l_p.qbelo_prob1_1, 0));
   win_matrix = log.(transpose(reshape(win_vec,nweeks,nteams)));
   win_matrix[win_matrix.==-Inf] .= -1e10;

   setdiff(remaining_teams_vec,history_of_picks_enumerate)
   remaining_teams = size(remaining_teams_vec,1)

   end_pred = min(nweeks,current_week+forward_length-1)
   sol = solve_IP(remaining_teams, end_pred-current_week+1,win_matrix[remaining_teams_vec,current_week:end_pred],2)

   team_pick = String[]
   for week_iter = 1:forward_length
      push!(team_pick,teams[Bool.(sol[:,week_iter])][1]);
   end

   println(team_pick)
end

alldata, teams, nteams,weeks,nweeks = import_data()

current_week = 1;
#forward_length of 1 means a greedy algorithm (only the current week's game)
forward_length = 8;
#e.g., history_of_picks = ["TEN"]
history_of_picks = [];
run_estimate(current_week, forward_length, history_of_picks,alldata, teams, nteams,weeks,nweeks)
