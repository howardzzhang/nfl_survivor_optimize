using JuMP, DataFrames, CSV, Dates, Statistics, Evolutionary, Random, HTTP, Plots
import HiGHS
include("util.jl")

#code implements modified version of Bergman and Imbrogno (2017), https://pubsonline.informs.org/doi/10.1287/opre.2017.1633
function import_data()
   datafile="https://projects.fivethirtyeight.com/nfl-api/nfl_elo.csv"
   dat = HTTP.get(datafile)
   main_data = CSV.read(dat.body, DataFrame)
   #exclude COVID year
   alldata = main_data[((main_data.season .>= 1990) .& (main_data.season .!= 2020) .& (main_data.season .< 2022)),:];
   alldata = alldata[ismissing.(alldata.playoff),:];
   alldata.result1 = alldata.score1 .> alldata.score2
   alldata.dayofweek = dayofweek.(alldata.date);
   seasons = unique(alldata.season);
   teams = unique(alldata.team1);
   sort!(teams)
   nteams = size(teams,1);

   #get week of play
   week_nfl = ones(size(alldata,1));
   for i = 2:size(alldata,1)
       if ((alldata.season[i] == alldata.season[i-1]) & (((alldata.dayofweek[i-1] < 3) & (alldata.dayofweek[i] >= 3)) | (alldata.date[i] -alldata.date[i-1]>=Dates.Day(6))))
          week_nfl[i] = week_nfl[i-1]+1;
       elseif (alldata.season[i] == alldata.season[i-1])
          week_nfl[i] = week_nfl[i-1];
       end
   end
   alldata.week = week_nfl;
   alldata = alldata[alldata.week.<=17,:];
   return (alldata, teams, nteams, seasons)
end

alldata, teams, nteams, seasons = import_data()

function generate_data(alldata, teams,nteams)
   nseasons = size(seasons,1);
   #home-field adjustment
   HFA = 48;
   #REST = 25;
   win_matrix_all_seasons = Array{Array{Array{Float64,2},1},1}(undef,nseasons);
   win_outcomes_matrix_seasons = Array{Array{Float64},1}(undef,nseasons);
   win_matrix_act_seasons = Array{Array{Float64},1}(undef,nseasons);
   nweeks_seasons = Array{Float64}(undef,nseasons);
   #generate data for each season
   for season = 1:nseasons
      season_year = seasons[season];
      test_data = alldata[alldata.season.==season_year,:];
      test_data.elo1 = test_data.elo1_pre+test_data.qb1_adj;
      test_data.elo2 = test_data.elo2_pre+test_data.qb2_adj;
      test_data.postelo1 = test_data.elo1_post+test_data.qb1_adj;
      test_data.postelo2 = test_data.elo2_post+test_data.qb2_adj;

      weeks = unique(test_data.week);
      sort!(weeks)
      nweeks = size(weeks,1);
      nweeks_seasons[season] = nweeks;

      l_p = crossjoin(DataFrame(teams=teams), DataFrame(week=weeks));
      l_p = leftjoin(l_p,test_data[:,[:team1,:week,:qbelo_prob1,:result1]],on=[:teams => :team1,:week])
      l_p = leftjoin(l_p,test_data[:,[:team2,:week,:qbelo_prob1,:result1]],on=[:teams => :team2,:week],makeunique=true)

      #this uses actual probabilities, which we do not observe at time t
      sort!(l_p,[:teams,:week])
      win_vec = ifelse.(ismissing.(l_p.qbelo_prob1) .& ismissing.(l_p.qbelo_prob1_1), 0, coalesce.(l_p.qbelo_prob1, 0) .+ coalesce.(1 .- l_p.qbelo_prob1_1, 0));
      win_matrix_act = log.(transpose(reshape(win_vec,nweeks,nteams)));
      win_matrix_act[win_matrix_act.==-Inf] .= -1e10;
      win_matrix_act_seasons[season] = win_matrix_act;

      # generate predicted probabilities using current/known ELO
      win_matrix_all = Array{Array{Float64, 2},1}(undef,nweeks);
      for startpoint = 1:nweeks
         temp_data = test_data;
         if startpoint > 1
            initial_elo = test_data[(test_data.week.==startpoint) ,[:week,:team1,:team2,:elo1,:elo2]];
            initial_elo_past = test_data[(test_data.week.==(startpoint-1)) ,[:week,:team1,:team2,:postelo1,:postelo2]];
            rename!(initial_elo_past,[:postelo1,:postelo2] .=> [:elo1,:elo2]);
            append!(initial_elo,initial_elo_past);
            initial_elo1 = initial_elo[:,[:week,:team1,:elo1]];
            rename!(initial_elo1,[:week,:team,:elo])
            initial_elo2 = initial_elo[:,[:week,:team2,:elo2]];
            rename!(initial_elo2,[:week,:team,:elo])
            append!(initial_elo1,initial_elo2)
            #obtain the latest week of elo
            initial_elo1 = combine(first, groupby(sort(initial_elo1,:week, rev=true), :team))
            select!(initial_elo1,Not(:week))
         else
            initial_elo = test_data[(test_data.week.==startpoint) ,[:team1,:team2,:elo1,:elo2]];
            initial_elo1 = initial_elo[:,[:team1,:elo1]];
            rename!(initial_elo1,[:team,:elo])
            initial_elo2 = initial_elo[:,[:team2,:elo2]];
            rename!(initial_elo2,[:team,:elo])
            append!(initial_elo1,initial_elo2)
         end

         temp_data = leftjoin(temp_data,initial_elo1,on=[:team1 => :team])
         rename!(temp_data,:elo => :elo1_fix)
         temp_data = leftjoin(temp_data,initial_elo1,on=[:team2 => :team])
         rename!(temp_data,:elo => :elo2_fix)
         temp_data.pwin1 = compute_win_prob.(temp_data.elo1_fix-temp_data.elo2_fix+HFA*(temp_data.neutral.==0));
         # testing purposes
         #temp_data[temp_data.week.==startpoint,:pwin1]  .= temp_data[temp_data.week.==startpoint,:qbelo_prob1];
         l_p_temp = leftjoin(l_p,temp_data[:,[:team1,:week,:pwin1]],on=[:teams => :team1,:week])
         l_p_temp = leftjoin(l_p_temp,temp_data[:,[:team2,:week,:pwin1]],on=[:teams => :team2,:week],makeunique=true)
         sort!(l_p_temp,[:teams,:week])
         win_vec = ifelse.(ismissing.(l_p_temp.pwin1) .& ismissing.(l_p_temp.pwin1_1), 0, coalesce.(l_p_temp.pwin1, 0) .+ coalesce.(1 .- l_p_temp.pwin1_1, 0));
         win_matrix = log.(transpose(reshape(win_vec,nweeks,nteams)));
         win_matrix[win_matrix.==-Inf] .= -1e10;
         win_matrix_all[startpoint] = win_matrix;
      end

      sort!(l_p,[:teams,:week])
      win_outcomes_vec = ifelse.(ismissing.(l_p.result1) .& ismissing.(l_p.result1_1), 0, coalesce.(l_p.result1, 0) .+ coalesce.(1 .- l_p.result1_1, 0));
      win_outcomes_matrix = transpose(reshape(win_outcomes_vec,nweeks,nteams));

      win_matrix_all_seasons[season] = win_matrix_all;
      win_outcomes_matrix_seasons[season] = win_outcomes_matrix;
   end
   return (win_matrix_all_seasons, win_outcomes_matrix_seasons,win_matrix_act_seasons,nseasons,nweeks_seasons,nseasons)
end

win_matrix_all_seasons, win_outcomes_matrix_seasons,win_matrix_act_seasons,nseasons,nweeks_seasons,nseasons = generate_data(alldata, teams,nteams);

global const current_min = Vector{Ref{Float64}}([1e9]);
global const sol_min =  Vector{Ref{Int64}}(undef,16);

function Evolutionary.trace!(record::Dict{String,Any}, objfun, state, population, method::GA, options)
   global sol_min
   global current_min
   idx = sortperm(state.fitpop)
   if state.fitpop[idx[1]] < current_min[1][]
      current_min[1] = state.fitpop[idx[1]];
      temp = population[idx[1]];
      @inbounds for p = 1:16
         sol_min[p] = temp[p];
      end
   end
end

function ga_optimize(win_matrix_all_seasons, win_outcomes_matrix_seasons,win_matrix_act_seasons,nseasons,nweeks_seasons,nteams)
   #now use GA to optimize
   #notice that in the last week, can only have a maximum look-forward of 1, optimize over 16 weeks
   npop=160;
   compute_performance_anonymous(look_forward) = compute_performance(look_forward,win_matrix_all_seasons,win_outcomes_matrix_seasons,win_matrix_act_seasons,nseasons,nweeks_seasons,nteams,1);
   upper = reverse(collect(2:17));
   lower = ones(Int64,16);
   options =
      Evolutionary.Options(show_trace=true,iterations=40, store_trace=true)
   optimizer = GA(;
      populationSize = npop,
      selection = tournament(5),
      crossover = SPX,
      mutation = MIPM(lower,upper),
      mutationRate = 0.05,
      crossoverRate = 0.8
      #epsilon = population_size ÷ 5,
   )
   x0 = Array{Array{Int64,1},1}(undef,npop);
   for p = 1:npop
      temp = [randperm(n)[1] for n = 2:17];
      x0[p] = reverse(temp)[:];
   end
   sol = Evolutionary.optimize(compute_performance_anonymous,BoxConstraints(lower, upper), x0, optimizer, options)
   return sol
end

function compute_performance(look_forward,win_matrix_all_seasons,win_outcomes_matrix_seasons,win_matrix_act_seasons,nseasons,nweeks_seasons,nteams,typereturn)
   survival = zeros(nseasons);
   log_likelihood = zeros(nseasons);
   for season in 1:nseasons
      win_matrix_all = win_matrix_all_seasons[season];
      win_outcomes_matrix = win_outcomes_matrix_seasons[season];
      nweeks = Int64(nweeks_seasons[season]);
      if typereturn == 2
         win_matrix_act = win_matrix_act_seasons[season];
      end
      sol = zeros(nteams,nweeks);
      remaining_teams = nteams
      remaining_teams_vec = collect(1:nteams);

      for startpoint = 1:nweeks
         if startpoint < nweeks
            looking_forward_internal = Int64(look_forward[startpoint]);
         else
            looking_forward_internal = 1;
         end
         win_matrix = win_matrix_all[startpoint];
         end_pred = min(nweeks,startpoint+looking_forward_internal-1)
         temp = solve_IP(remaining_teams, end_pred-startpoint+1,win_matrix[remaining_teams_vec,startpoint:end_pred],1)
         sol[remaining_teams_vec,startpoint] .= temp;
         deleteat!(remaining_teams_vec, temp .== 1);
         remaining_teams -= 1
      end
      if typereturn == 1
         temp = vec(transpose(sum(sol .* win_outcomes_matrix,dims=1)));
         if isnothing(findfirst(temp.==0))
            survival[season] = nweeks
         elseif isnothing(findnext(temp.==0,findfirst(temp.==0)+1))
            survival[season] = nweeks
         else
            survival[season] = findnext(temp.==0,findfirst(temp.==0)+1)
         end
      elseif typereturn == 2
         log_likelihood[season] = sum(sol.*win_matrix_act);
      end
   end
   if typereturn == 1
      return 1 ./ mean(survival)
   elseif typereturn == 2
      return -mean(log_likelihood)
   end
end

sol = ga_optimize(win_matrix_all_seasons, win_outcomes_matrix_seasons,win_matrix_act_seasons,nseasons,nweeks_seasons,nteams);

function single_length(win_matrix_all_seasons, win_outcomes_matrix_seasons,win_matrix_act_seasons,nseasons,nweeks_seasons,nteams)
   survival = zeros(nseasons,17);
   log_likelihood = zeros(nseasons,17);
   for potential_length = 1:17
      for season = 1:nseasons
         win_matrix_all = win_matrix_all_seasons[season];
         win_outcomes_matrix = win_outcomes_matrix_seasons[season];
         nweeks = Int64(nweeks_seasons[season]);
         win_matrix_act = win_matrix_act_seasons[season];

         display([season potential_length])
         sol = zeros(nteams,nweeks);
         remaining_teams = nteams
         remaining_teams_vec = collect(1:nteams);

         for startpoint = 1:nweeks
            win_matrix = win_matrix_all[startpoint];
            end_pred = min(nweeks,startpoint+potential_length-1)
            temp = solve_IP(remaining_teams, end_pred-startpoint+1,win_matrix[remaining_teams_vec,startpoint:end_pred],1)
            sol[remaining_teams_vec,startpoint] .= temp;
            deleteat!(remaining_teams_vec, temp .== 1);
            remaining_teams -= 1
         end
         temp = vec(transpose(sum(sol .* win_outcomes_matrix,dims=1)));
         log_likelihood[season,potential_length] = sum(sol.*win_matrix_act);
         if isnothing(findfirst(temp.==0))
            survival[season,potential_length] = nweeks
         elseif isnothing(findnext(temp.==0,findfirst(temp.==0)+1))
            survival[season,potential_length] = nweeks
         else
            survival[season,potential_length] = findnext(temp.==0,findfirst(temp.==0)+1)
         end
      end
   end
   mean_sol = mean(survival,dims=1)
   median_sol = median(survival,dims=1)
   display([mean_sol median_sol])
   _,optimal_mean_sol = findmax(mean_sol);
   _,optimal_median_sol = findmax(median_sol);
   display([optimal_mean_sol optimal_median_sol])

   mean_log_likelihood = mean(log_likelihood,dims=1)
   median_log_likelihood = median(log_likelihood,dims=1)
   display([mean_log_likelihood median_log_likelihood])
   _,optimal_mean_log_likelihood = findmax(mean_log_likelihood[1:17]);
   _,optimal_median_log_likelihood = findmax(median_log_likelihood[1:17]);
   display([optimal_mean_log_likelihood optimal_median_log_likelihood])

   plot(1:17,transpose(mean_sol)[:], title = "Expected Survival Length (Two Lives)", xlabel="Look Forward")
   savefig("constant_lookforward_survivalperiod.png")
   plot(1:17,transpose(mean_log_likelihood)[:], title = "Expected log Likelihood", xlabel="Look Forward")
   savefig("constant_lookforward_loglikelihood.png")
end

function optimal_fullinfo(win_matrix_all_seasons, win_outcomes_matrix_seasons,win_matrix_act_seasons,nseasons,nweeks_seasons,nteams)
   survival = zeros(nseasons);
   log_likelihood = zeros(nseasons);
   potential_length = 17;
   startpoint = 1;
   for season = 1:nseasons
      win_outcomes_matrix = win_outcomes_matrix_seasons[season];
      nweeks = Int64(nweeks_seasons[season]);
      win_matrix_act = win_matrix_act_seasons[season];
      #display([season potential_length])

      end_pred = min(nweeks,startpoint+potential_length-1)
      sol = solve_IP(nteams, end_pred-startpoint+1,win_matrix_act[:,startpoint:end_pred],2)

      temp = vec(transpose(sum(sol .* win_outcomes_matrix,dims=1)));
      log_likelihood[season] = sum(sol.*win_matrix_act);
      if isnothing(findfirst(temp.==0))
         survival[season] = nweeks
      elseif isnothing(findnext(temp.==0,findfirst(temp.==0)+1))
         survival[season] = nweeks
      else
         survival[season] = findnext(temp.==0,findfirst(temp.==0)+1)
      end
   end
   mean_sol = mean(survival)
   median_sol = median(survival)
   display([mean_sol median_sol])

   mean_log_likelihood = mean(log_likelihood)
   median_log_likelihood = median(log_likelihood)
   display([mean_log_likelihood median_log_likelihood])
end
