classdef mcmcInfer < infEngine
  % Markov chain Monte Carlo 
  
  properties
    Nsamples; Nburnin; thin;
    samples; acceptRatio;
    proposalFn; targetFn; xinitFn;
    visVars; visValues; hidVars;
    evidenceEntered= false;
    method; 
    seeds;
  end
 
  methods
    function eng = mcmcInfer(varargin)
      % Method can be one of: gibbs, metrop or mh
      [Nsamples, Nburnin, thin, method, seeds] = process_options(varargin, ...
        'Nsamples', 1000, 'Nburnin', 100, 'thin', 1, 'method', [], 'seeds', 1);
      eng.Nsamples = Nsamples;
      eng.Nburnin = Nburnin;
      eng.method = method;
      eng.thin = thin;
      eng.seeds = seeds;
      eng.visVars = NaN; eng.visValues = NaN;
    end
    
    function [X, naccept] = mcmcSample(eng)
      if isnan(eng.visVars), error('must call enterEvidence first'); end
      x = initChain(eng);
      d = length(x);
      Nseeds = length(eng.seeds);
      X = zeros(eng.Nsamples, d, Nseeds);
      naccept = zeros(1,Nseeds);
      for i=1:Nseeds
        setSeed(eng.seeds(i));
        [X(:,:,i), naccept(i)] = mcmcSampleHelper(eng);
        restoreSeed;
      end
    end
    
    function [X, naccept] = mcmcSampleHelper(eng)
      x = initChain(eng);
      keep = 1;
      naccept = 0;
      if strcmpi(eng.method, 'mh') || strcmpi(eng.method, 'metrop')
        logpx = target(eng, x);
      end
      S = (eng.Nsamples*eng.thin + eng.Nburnin);
      d = length(x);
      X = zeros(eng.Nsamples, d);
      u = rand(S,1); % move outside main loop to speedup MH
      for iter=1:S
        switch lower(eng.method)
          case 'gibbs'
            x = gibbsUpdate(eng, x);
            accept = 1;
          case {'mh', 'metrop'}
            [x, accept, logpx] = mhUpdate(eng, x, logpx, u(iter));
        end
        naccept = naccept + accept;
        if (iter > eng.Nburnin) && (mod(iter, eng.thin)==0)
          X(keep,:) = x; keep = keep + 1;
        end
      end
    end
    
    function x = gibbsUpdate(eng, x)
      H = eng.hidVars;
      for i=H(:)' % only resample hidden nodes
        x(i) = sampleFullCond(eng, x, i); % child method
      end
    end
     
    % typically this will be overloaded by the child class
     function [xprime] = proposal(eng, x)
        [xprime] = feval(eng.proposalFn, x);
     end
    
      % typically this will be overloaded by the child class
     function logp = target(eng, x)
        logp = feval(eng.targetFn, x);
     end
    
      % typically this will be overloaded by the child class
     function x = initChain(eng)
         x = feval(eng.xinitFn);
     end
      
    function [xnew, accept, logpNew] = mhUpdate(eng, x, logpOld, u)
      if strcmpi(eng.method, 'metrop')
        [xprime] = proposal(eng, x);
        probOldToNew = 1; probNewToOld = 1;
      else
        [xprime, probOldToNew, probNewToOld] = proposal(eng, x);
      end
      logpNew = target(eng, xprime); % child method
      alpha = exp(logpNew - logpOld);
      alpha = alpha * (probNewToOld/probOldToNew);  % Hastings correction for asymmetric proposals
      r = min(1, alpha);
      %u = rand(1,1);
      if u < r
        xnew = xprime;
        accept = 1;
      else
        accept = 0;
        xnew = x;
        logpNew = logpOld;
      end
    end
  
     %{
      function X = mhSample(eng)
       if ~eng.evidenceEntered, error('must call enterEvidence first'); end
       target = makeTarget(eng); % child method
       proposal = makeProposal(eng); % child method
       x = initChain(eng); % child methd
       X = genericMH(target, proposal, x, eng.Nburnin, eng.Nsamples);
     end
   %}
     
   function eng = enterEvidence(eng, visVars, visValues)
      % p(Xh|Xvis=vis)
      d = ndims(eng);
      eng.visVars = visVars; eng.visValues = visValues;
      eng.hidVars = setdiff(1:d, visVars);
      S = eng.Nsamples*eng.thin + eng.Nburnin;
      switch eng.method
        case 'gibbs2' % debug
          [eng.samples] = gibbsSample2(eng);
          naccept = S;
        otherwise
          [eng.samples, naccept] = mcmcSample(eng);
      end
      eng.acceptRatio = naccept/S;
      eng.evidenceEntered = true;
   end
   
   function [X, eng] = sample(eng, n)
     % X(i,:) = sample for i=1:n
     if ~eng.evidenceEntered
       eng = enterEvidence(eng, [], []);  % compute joint
     end
     X = eng.samples;
     if size(X,1) > n
       X = X(1:n, :);
     elseif size(X,1) < n
       fprintf('warning: only returnin %d samples, not %d as requested\n', ...
         size(X,1), n);
     end
   end
   
   function [postQuery, eng] = marginal(eng, queryVars)
     if ~eng.evidenceEntered
       eng = enterEvidence(eng, [], []);  % compute joint
     end
     postQuery = sampleDist(eng.samples(:,queryVars));
   end

    
  end % methods

   %% Static
  methods(Static = true)
    
    
    function demoConvDiagGmm()
      m = gaussMixDist('K', 2, 'mu', [-50 50], 'Sigma', reshape([10^2 10^2], [1 1 2]), ...
        'mixweights', [0.3 0.7]);
      seeds = 1:3;
      sigmas = [10 100 500];
      N = 1000;
      for s=1:length(sigmas)
        eng = mcmcInfer('Nsamples', N, 'Nburnin', 0, 'method', 'metrop', 'seeds', seeds);
        eng.targetFn = @(x) (logprob(m,x));
        eng.proposalFn = @(x) (x + (sigmas(s) * randn(1,1)));
        eng.xinitFn = @() (m.mu(2));
        eng = enterEvidence(eng, [], []);
        X = eng.samples;
        mcmcInfer.plotConvDiagnostics(X, 1, sprintf('sigma prop %5.3f', sigmas(s)));
      end
    end
    
    
    function plotConvDiagnostics(X, dim, ttl)
      % Plot trace plot, smoothed trace plot, and ACF
      % X(samples, dimensions, chain/seed)
      if nargin < 2, dim = 1; end
      if nargin < 3, ttl = ''; end
      nseeds = size(X,3);
      colors = {'r', 'g', 'b', 'k'};
      % Trace plots
      %h=figure; set(h,'name', ttl);
      figure;
      hold on;
      for i=1:nseeds
        plot(X(:,dim,i), colors{i});
      end
      Rhat = epsr(X(:,dim,:));
      title(sprintf('%s, Rhat = %5.3f', ttl, Rhat))
      % Smoothed trace plots 
      figure; hold on
      for i=1:nseeds
        movavg = filter(repmat(1/50,50,1), 1, X(:,dim,i));
        plot(movavg,  colors{i});
      end
      title(sprintf('%s, Rhat = %5.3f', ttl, Rhat))
      % Plot auto correlation function for 1 chain
      figure;
      stem(acf(X(:,dim,1), 20));
      title(ttl)
    end
    
    function demoGmmBurnin()
      seeds = 1:3;
      sigmas = [10 100 500];
      %sigmas = [10];
      N = 1000;
      X = zeros(N,  length(seeds), length(sigmas));
      for s=1:length(sigmas)
        m = gaussMixDist('K', 2, 'mu', [-50 50], 'Sigma', reshape([10^2 10^2], [1 1 2]), ...
          'mixweights', [0.3 0.7]);
        eng = mcmcInfer('Nsamples', N, 'Nburnin', 0, 'method', 'metrop', 'seeds', seeds);
        eng.targetFn = @(x) (logprob(m,x));
        eng.proposalFn = @(x) (x + (sigmas(s) * randn(1,1)));
        eng.xinitFn = @() (m.mu(2));
        eng = enterEvidence(eng, [], []);
        X(:,:,s) = eng.samples;
      end
      colors = {'r', 'g', 'b', 'k'};
      % Trace plots
      for s=1:length(sigmas)
        figure; hold on;
        for i=1:length(seeds)
          plot(X(:,i,s), colors{i});
        end
        Rhat(s) = epsr(X(:,:,s));
        title(sprintf('sigma prop = %5.3f, Rhat = %5.3f', sigmas(s), Rhat(s)))
      end
      % Smoothed trace plots
      for s=1:length(sigmas)
        figure; hold on
        for i=1:length(seeds)
          movavg = filter(repmat(1/50,50,1), 1, X(:,i,s));
          plot(movavg,  colors{i});
        end
        title(sprintf('sigma prop = %5.3f, Rhat = %5.3f', sigmas(s), Rhat(s)))
      end
      % Plot auto correlation function for 1 chain
      for s=1:length(sigmas)
        figure;
        stem(acf(X(:,1,s), 20));
        title(sprintf('sigma prop = %5.3f', sigmas(s)))
      end
      
    end
    
    
    function demoProposalGmm()
      sigmas = [10 100 500];
      for i=1:length(sigmas)
        mcmcInfer.helperProposalGmm(sigmas(i));
      end
    end
    
    function x=helperProposalGmm(sigma_prop)
      % based on code by Christoph Andrieu
      setSeed(0);
      m = gaussMixDist('K', 2, 'mu', [-50 50], 'Sigma', reshape([10^2 10^2], [1 1 2]), ...
        'mixweights', [0.3 0.7]);
      eng = mcmcInfer('Nsamples', 1000, 'Nburnin', 0, 'method', 'metrop');
      eng.targetFn = @(x) (logprob(m,x));
      eng.proposalFn = @(x) (x + (sigma_prop * randn(1,1)));
      eng.xinitFn = @() (m.mu(2));
      eng = enterEvidence(eng, [], []);
      x = eng.samples;
     
      figure;
      nb_iter = eng.Nsamples;
      x_real = linspace(-100, 100, nb_iter);
      y_real = exp(logprob(m, x_real(:)));
      Nbins = 100;
      plot3(1:nb_iter, x, zeros(nb_iter, 1))
      hold on
      plot3(ones(nb_iter, 1), x_real, y_real)
      [u,v] = hist(x, linspace(-100, 100, Nbins));
      plot3(zeros(Nbins, 1), v, u/nb_iter*Nbins/200, 'r')
      hold off
      grid
      view(60, 60)
      xlabel('Iterations')
      ylabel('Samples')
      title(sprintf('MH with N(0,%5.3f^2) proposal', sigma_prop))
    end
    
  end
  
end