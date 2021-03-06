function [beta,offset_par,n_iter] = l1l2_learn(X,Y,tau,varargin)
% L1L2_LEARN  computes l1l2 regularization followed by a de-biasing step 
% performed via regularized least squares (RLS)

% INPUT:
% X....................a nxd matrix, collecting n samples of dimension d 
% Y....................a nx1 vector of labels
% tau..................the weight of the l1 term
% OPTIONAL INPUT:
% A list of couples ('PropertyName',PropertyValue)
% 'PropertyName'.......a string that can be:
%                      -'RLS_par': if given apply RLS-debiasing 
%                       with input parameter RLS_par
%                      -'smooth_par': (default is 0) sets the l2 parameter 
%                        equal to SMOOTH_PAR
%                      -'max_iter': (default is 1e5) maximum number of iterations
%                      -'tolerance': (default is 1e-6) tolerance for stopping the iterations.
%                      -'offset': (default is true) computes the (unpenalized) offset                      
% PropertyValue........corresponding value
% smooth_par...........parameter controlling the weight of the l2 term, 
%                      which is ||X||^2*smooth_par/(2n) 
% beta0................initialization vector for FISTA (defalut = 0)
% L0...................parameter that changes the step size (default = A/n)
% max_iter.............maximum number of iteration (default = 1e5)
% toll.................relative tolerance for stopping (default = 1e-6)

% 
% [beta] = L1L2_LEARN(X,Y,tau) computes l1 solution with sparsity 
%   parameter tau (tau must be > 0) and l2 parameter 0. It implements a
%   continuation method. If tau is an array of increasing values 
%   for the sparsity parameter, computes the solution for decreasing values
%   of tau(2:end) with loose tolerance using a warm restart strategy 
%   and then use the last solution as initialization for computing, 
%   with stricter tolerance, the solution for tau(1).
% 
% [beta,offset_par] = L1L2_LEARN(X,Y,tau) also returns the offset of the
%   learned model (it's 0 if property 'center' is false). 
% 
% [BETA,offset_par,n_iter] = L1L2_LEARN(X,Y,TAU) also returns the total number of 
%   iterations.
% 
% L1L2_LEARN(...,'PropertyName',PropertyValue,...) sets properties to the
%   specified property values.
%       -'RLS_par': if given apply RLS-debiasing with input parameter
%       RLS_par
%       -'smooth_par': (default is 0) sets l2 parameter equal to SMOOTH_PAR
%       times the step_size which is computed internally
%       -'max_iter': (default is 1e5) maximum number of iterations
%       -'tolerance': (default is 1e-6) tolerance for stopping the iterations.
%       -'offset': (default is true) computes the (unpenalized) offset
%       parameter of the linear model
 
if nargin<3; error('too few inputs!'); end

% DEFAULT PARAMETERS
smooth_par = 0;
max_iter = 1e5;
tol = 1e-6;
offset = true;


% OPTIONAL PARAMETERS
args = varargin;
nargs = length(args);
for i=1:2:nargs
    switch args{i},
		case 'RLS_par'
            RLS_par = args{i+1};
		case 'smooth_par'
            smooth_par = args{i+1};
		case 'max_iter'
            max_iter = args{i+1};
		case 'tolerance'
            tol = args{i+1};
    end
end

% center data by subtracting means as a way to later compute the offset (if offset=true)
[X,Y,meanX,meanY] = centering(X,Y,offset);

% in order to accelerate the computation of the solution corresponding to
% tau,  
% evaluates solutions for larger vaues of the parameter with looser tolerance, and
% use input (or default) tolerance to compute the solution corresponding to tau
if length(tau)==1;
    ntau =10;        
    % estimate the maximum value of the sparsity parameter (larger
    % values should produce null solutions)
    tau_max = l1l2_tau_max(X,Y);
    if tau_max<tau;
        tau_values = tau;
        ntau = 1;
    else %set the values of the vector tau following a geometric series.
        tau_values = [tau tau*((tau_max/tau)^(1/(ntau-1))).^(1:(ntau-1))]; 
    end
else
    tau_values = tau;
    ntau = length(tau_values);
end
[n,d] = size(X);

% looser tolerance for computing solutions for larger values of the
% parameter
tol = ones(ntau,1).*tol;
tol(2:end) = tol(2:end).*100;

% the Lipschitz constant of the datafit term
L0 = normest(X)^2/n;


% initialization
n_iter = zeros(ntau,1);%initialization for the numbers of iterations
beta0 = zeros(d,1);    %starting point in the iterative algorithm
sparsity = 0; %initialization for the number of selected varaibles

for t = ntau:-1:1;
    % when smooth_par=0, exit if the algorithm selected more than n 
    % variables for the previously computed values of tau,   
    % otherwise compute a new solution using previous solution as
    % initialization
    if and(smooth_par==0,sparsity>=n);
        beta =rls_algorithm(X,Y);
        break
    else
        [beta,n_iter(t)] = l1l2_algorithm(X,Y,tau_values(t),smooth_par,beta0,L0,max_iter,tol(t));
        sparsity = sum(beta~=0); % number of selected variables
        beta0 = beta; 
    end
end
n_iter = sum(n_iter);
selected = beta~=0; % selected variables

% RLS-debiasing
if exist('RLS_par','var')
    beta = zeros(d,1);
	beta(selected) = rls_algorithm(X(:,selected),Y,RLS_par);  
end

%Compute offset parameter
offset_par = meanY-meanX*beta;
