classdef multinomDist < vecDist
  
  properties
    N; 
    mu;
  end
  
  
  %% Main methods
  methods 
    function obj =  multinomDist(N,mu)
      if nargin == 0;
        N = []; mu = [];
      end
      obj.N = N;
      obj.mu = mu;
    end
    
    function plot(obj) % over-ride default
      figure; bar(obj.mu);
      title(sprintf('Mu(%d,:)', obj.N))
    end
  
    
    function m = mean(obj)
     checkParamsAreConst(obj)
      m = obj.N * obj.mu;
    end
    
   
    function X = sample(obj, n)
       % X(i,:) = random vector (of length ndims) of ints that sums to N, for i=1:n
       checkParamsAreConst(obj)
       if nargin < 2, n = 1; end
       if statsToolboxInstalled
          X = mnrnd(obj.N, obj.mu, n);
       else
         p = repmat(obj.mu(:), 1, n);
         X = sample_hist(p, obj.N)';
       end
     end
    
     function logp = logprob(obj, X)
       % p(i) = log p(X(i,:))
       checkParamsAreConst(obj)
       n = size(X,1);
       p = repmat(obj.mu,n,1);
       xlogp = sum(X .* log(p), 2);
       logp = factorialln(obj.N) - sum(factorialln(X), 2) + xlogp; 
       % debugging
       %logp2 = log(mnpdf(X,obj.mu));
       %assert(approxeq(logp, logp2))
     end


     function logZ = lognormconst(obj)
       logZ = 0;
     end
     
     function mm = marginal(m, queryVars)
      % p(Q)
      checkParamsAreConst(obj)
      dims = queryVars;
      mm = multinomDist(m.N, m.mu(dims));
     end
    
     
     function obj = fit(obj, varargin)
       % m = fit(model, 'name1', val1, 'name2', val2, ...)
       % Arguments are
       % data - data(i,:) = vector of counts for trial i
       % suffStat - SS.counts(j), SS.N = total amount of data
       % method -  'map' or 'mle'
       [X, suffStat, method] = process_options(...
         varargin, 'data', [], 'suffStat', [], 'method', 'mle');
       if isempty(suffStat), suffStat = multinomDist.mkSuffStat(X); end
       switch method
         case 'mle'
           obj.mu =  suffStat.counts / suffStat.N;
         case 'map'
           switch class(obj.mu)
             case 'dirichletDist'
               d = ndims(obj);
               obj.mu  = (suffStat.counts + obj.alpha - 1) / (suffStat.N + sum(obj.alpha) - d);
             otherwise
               error(['cannot handle mu of type ' class(obj.mu)])
           end
         otherwise
           error(['unknown method ' method])
       end
     end

     function obj = inferParams(obj, varargin)
       % m = inferParams(model, 'name1', val1, 'name2', val2, ...)
       % Arguments are
       % data - data(i,:) = vector of counts for trial i
       % suffStat - SS.counts(j), SS.N = total amount of data
       [X, suffStat] = process_options(...
         varargin, 'data', [], 'suffStat', []);
       if isempty(suffStat), suffStat = multinomDist.mkSuffStat(X); end
       switch class(obj.mu)
         case 'dirichletDist'
           obj.mu = dirichletDist(obj.mu.alpha + suffStat.counts);
         otherwise
           error(['cannot handle mu of type ' class(obj.mu)])
       end
     end
     
  end



  %% static
  methods(Static = true)
      function SS = mkSuffStat(X)
       SS.counts = sum(X,2);
       n = size(X,1);
       SS.N = sum(X(:));
      end
       
     
    function demoPlot(seed)
      if nargin < 1, seed = 1; end
      rand('state', seed); randn('state', seed);
      pr = [0.1, 0.1, 0.2 0.5, 0.1];
      N = 10;
      prStr = sprintf('%3.1f ', pr);
      p = multinomDist(N, pr);
      n = 5;
      X = sample(p, n);
      figure;
      for i=1:n
        subplot(n,1,i); bar(X(i,:));
        set(gca,'ylim',[0 10]);
        if i==1, title(sprintf('samples from Mu(%d, [%s])',N, prStr)); end
      end
    end
  end
  
  %% Private methods
  methods(Access = 'protected')
   
    function checkParamsAreConst(obj)
      p = isa(obj.mu, 'double') && isa(obj.N, 'double');
      if ~p
        error('parameters must be constants')
      end
    end

  end
  
end