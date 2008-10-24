classdef logregDist < condProbDist
  
  properties
    w; 
    transformer;
  end
  
  %% Main methods
  methods 
    function m = logregDist(varargin)
      [transformer,  w] = process_options(...
        varargin, 'transformer', [], 'w', []);
      m.transformer = transformer;
      m.w = w;
    end
     
    
     function p = logprob(obj, X, y)
       % p(i) = log p(Y(i) | X(i,:), params), Y(i) = 0 or 1
       z = X*obj.w;
       logp1 = -log1p(-z); % -log(1+exp(-X*obj.w));
       logp0 = -log1p(z); % -log(1+exp(X*obj.w));
       ndx1 = find(y==1); ndx0 = find(y==0);
       n = length(y);
       p = zeros(n,1);
       p(ndx1) = logp1(ndx1);
       p(ndx0) = logp0(ndx0);
     end
     
     function pred = predict(obj, X, w)
       % X(i,:) is case i
       % p1(i) = Bernoulli(y|X(i,:))
       % yhat(i) = 0 or 1
       if nargin < 3, w = obj.w; end
       if ~isempty(obj.transformer)
         X = test(obj.transformer, X);
       end
       p1 = sigmoid(X*w);
       pred = bernoulliDist(p1);
       %yHat = (p1>0.5);
     end

     
     function pred = postPredict(obj, X, varargin)
       % pred(i) = Bernoulli(y|X(i,:)) for integral
       % pred(i).samples(s,i) = sampleDist(y|X(i,:)) for mc 
       % 'method' - one of {'mc', 'integral', 'plugin'}
       [method, Nsamples] = process_options(varargin, ...
         'method', 'integral', 'Nsamples', 100); 
       if ~isempty(obj.transformer)
         X = test(obj.transformer, X);
       end
       n = size(X,1);
       switch class(obj.w)
         case 'mvnDist'
           switch lower(method)
             case 'plugin'
               wMAP = obj.w.mu(:);
               p1 = sigmoid(X*wMAP);
               pred = BernoulliDist(p1);
             case 'mc'
               W = mvnrnd(obj.w.mu(:)', obj.w.Sigma, Nsamples)';
               p = sigmoid(X*W); % n * S 
               pred = sampleDist(p');
             case 'integral'
               p = sigmoidTimesGauss(X, obj.w.mu(:), obj.w.Sigma);
               pred = bernoulliDist(p);
             otherwise
               error(['cannot handle ' method])
           end
         otherwise
           error(['cannot handle ' class(obj.w)])
       end
     end
     
     function [obj, output] = fit(obj, varargin)
       % model = fit(model, 'name1', val1, 'name2', val2, ...)
       % Arguments are
       % 'X' - X(i,:) Do NOT include a column of 1's
       % 'y'- y(i) should be  in {0, 1}
       % 'prior' - one of { 'none', 'L2', 'L1'}
       % 'lambda' - >= 0
       % method - one of {'sgd', 'perceptron', 'boundoptRelaxed','boundoptStepwise', any minFunc method}
       %  where sgd = stochastic gradient descent,
       %   perceptron = approximate sgd
       % output returns results from the optimizer
       output = [];
       [X, y,  prior, lambda, method] = process_options(...
         varargin, 'X', [], 'y', [],  'prior', 'none', 'lambda', 0, 'method', 'newton');
       if ~isempty(obj.transformer)
         [X, obj.transformer] = train(obj.transformer, X);
       end
       if isempty(prior) && lambda > 0
         prior = 'L2';
       end
       switch lower(prior)
         case {'l2', 'none'}
           d = size(X,2);
           winit = zeros(d,1);
           options = struct('Display','none','Diagnostics','off','GradObj','on','Hessian','on');
           switch lower(method)
             case 'sgd',
               [obj.w, output] = logregSGD(X, y, lambda);
             case {'boundoptstepwise', 'boundoptrelaxed'}
               m = multinomLogregDist('nclasses', 2);
               y12 = y+1; % 1,2
               [m, output] = fit(m, 'X', X, 'y', y12, 'lambda', lambda, 'method', method);
               obj.w = m.w;
             case 'perceptron',
               [obj.w] = perceptron(X, y, lambda);
             otherwise 
               options.Method = method;
               [obj.w, f, exitflag, output] = minFunc(@logregNLLgradHess, winit, options, X, y, lambda);
           end
         otherwise
           error(['unrecognized prior ' prior])
       end
     end

      function obj = inferParams(obj, varargin)
       % model = fit(model, 'name1', val1, 'name2', val2, ...)
       % Arguments are
       % 'X' - X(i,:) Do NOT include a column of 1's
       % 'y'- y(i)
       % 'prior' - one of { 'L2'}
       % 'lambda' - >= precision of diagonal prior
       % method - one of {'laplace'}
       [X, y,  prior, lambda, method] = process_options(...
         varargin, 'X', [], 'y', [],  'prior', 'L2', 'lambda', 0, 'method', 'laplace');
       if ~isempty(obj.transformer)
         [X, obj.transformer] = train(obj.transformer, X);
       end
       done = false;
       if strcmpi(prior, 'l2') && strcmpi(method, 'laplace')
         d = size(X,2);
         winit = zeros(d,1);
         options = optimset('Display','none','Diagnostics','off','GradObj','on','Hessian','on');
         [wMAP] = fminunc(@logregNLLgradHess, winit, options, X, y, lambda);
         [nll, g, H] = logregNLLgradHess(wMAP, X, y, lambda); % H = hessian of neg log lik
         C = inv(H);
         obj.w = mvnDist(wMAP, C); %C  = inv Hessian(neg log lik)
         done = true;
       end
       assert(done);
      end
    
   
    
  end
  
  %% Demos
  methods(Static = true)
    
    function demoSat()
      setSeed(1);
      stat = load('satData.txt'); % Johnson and Albert p77 table 3.1
      % stat=[pass(0/1), 1, 1, sat_score, grade in prereq]
      % where the grade in prereq is encoded as A=5,B=4,C=3,D=2,F=1
      y = stat(:,1);
      N = length(y);
      X = [stat(:,4)];
      T = addOnesTransformer;
      obj = logregDist('transformer', T);
      obj = fit(obj, 'X', X, 'y', y);
      
      % MLE
      figure; hold on
      [X,perm] = sort(X,'ascend');
      [py] = mean(predict(obj, X));
      y = y(perm);
      plot(X, y, 'ko', 'linewidth', 3, 'markersize', 12);
      plot(X, py, 'rx', 'linewidth', 3, 'markersize', 12);
      set(gca, 'ylim', [-0.1 1.1]);
      
      % Bayes
      obj = inferParams(obj, 'X', X, 'y', y, 'lambda', 1e-3);
      figure; hold on
      subplot(1,3,1); plot(obj.w); xlabel('w0'); ylabel('w1'); title('joint')
      subplot(1,3,2); plot(marginal(obj.w,1),'plotArgs', {'linewidth',2}); xlabel('w0')
      subplot(1,3,3); plot(marginal(obj.w,2),'plotArgs', {'linewidth',2}); xlabel('w1')
      
      figure; hold on
      n = length(y);
      S = 100;
      ps = postPredict(obj, X, 'method', 'MC', 'Nsamples', S);
      for i=1:n
        psi = marginal(ps, i); 
        [Q5, Q95] = credibleInterval(psi);
        line([X(i) X(i)], [Q5 Q95], 'linewidth', 3);
        plot(X(i), median(psi), 'rx', 'linewidth', 3, 'markersize', 12);
      end
      plot(X, y, 'ko', 'linewidth', 3, 'markersize', 12);
      set(gca, 'ylim', [-0.1 1.1]);
      
      figure; hold on
      plot(X, y, 'ko', 'linewidth', 3, 'markersize', 12);
      for s=1:30
        psi = ps.samples(s,:);
        plot(X, psi, 'r-');
      end
    end
    
    function demoLaplaceGirolami()
      % Based on code written by Mark Girolami
      setSeed(0);
      % We generate data from two Gaussians:
      % x|C=1 ~ gauss([1,5], I)
      % x|C=0 ~ gauss([-5,1], 1.1I)
      N=30;
      D=2;
      mu1=[ones(N,1) 5*ones(N,1)];
      mu2=[-5*ones(N,1) 1*ones(N,1)];
      class1_std = 1;
      class2_std = 1.1;
      X = [class1_std*randn(N,2)+mu1;2*class2_std*randn(N,2)+mu2];
      y = [ones(N,1);zeros(N,1)];
      alpha=100; %Variance of prior (alpha=1/lambda) 
      
      %Limits and grid size for contour plotting
      Range=8;
      Step=0.1;
      [w1,w2]=meshgrid(-Range:Step:Range,-Range:Step:Range);
      [n,n]=size(w1);
      W=[reshape(w1,n*n,1) reshape(w2,n*n,1)];
      
      Range=12;
      Step=0.1;
      [x1,x2]=meshgrid(-Range:Step:Range,-Range:Step:Range);
      [nx,nx]=size(x1);
      grid=[reshape(x1,nx*nx,1) reshape(x2,nx*nx,1)];
      
      % Plot data and plug-in predictive
      figure;
      m = fit(logregDist, 'X', X, 'y', y);
      plotPredictive(mean(predict(m,grid)));
      title('p(y=1|x, wMLE)')
      
      % Plot prior and posterior
      eta=W*X';
      Log_Prior = log(mvnpdf(W, zeros(1,D), eye(D).*alpha));
      Log_Like = eta*y - sum(log(1+exp(eta)),2);
      Log_Joint = Log_Like + Log_Prior;
      figure;
      J=2;K=2;
      subplot(J,K,1)
      contour(w1,w2,reshape(-Log_Prior,[n,n]),30);
      title('Log-Prior');
      subplot(J,K,2)
      contour(w1,w2,reshape(-Log_Like,[n,n]),30);
      title('Log-Likelihood');
      subplot(J,K,3)
      contour(w1,w2,reshape(-Log_Joint,[n,n]),30);
      title('Log-Unnormalised Posterior')
      hold

      %Identify the parameters w1 & w2 which maximise the posterior (joint)
      [i,j]=max(Log_Joint);
      plot(W(j,1),W(j,2),'.','MarkerSize',40);
      %Compute the Laplace Approximation
      tic
      m = inferParams(logregDist, 'X', X, 'y', y, 'lambda', 1/alpha, 'method', 'laplace');
      toc
      wMAP = m.w.mu;
      C = m.w.Sigma;
      %[wMAP, C] = logregFitIRLS(t, X, 1/alpha);
      Log_Laplace_Posterior = log(mvnpdf(W, wMAP', C)+eps);
      subplot(J,K,4);
      contour(w1,w2,reshape(-Log_Laplace_Posterior,[n,n]),30);
      hold
      plot(W(j,1),W(j,2),'.','MarkerSize',40);
      title('Laplace Approximation to Posterior')

      
      % Posterior predictive
      % wMAP
      figure;
      subplot(2,2,1)
      plotPredictive(mean(postPredict(m, grid, 'method', 'plugin'))); 
      title('p(y=1|x, wMAP)')
      
      subplot(2,2,2); hold on
      S = 100;
      plot(X(find(y==1),1),X(find(y==1),2),'r.');
      plot(X(find(y==0),1),X(find(y==0),2),'bo');
      pred = postPredict(m, grid, 'method', 'MC', 'nsamples', S);
      for s=1:min(S,20)
        p = pred.samples(s,:);
        contour(x1,x2,reshape(p,[nx,nx]),[0.5 0.5]);
      end
      set(gca, 'xlim', [-10 10]);
      set(gca, 'ylim', [-10 10]);
      title('decision boundary for sampled w')
      
      subplot(2,2,3)
      plotPredictive(mean(pred));
      title('MC approx of p(y=1|x)')
      
      subplot(2,2,4)
      plotPredictive(mean(postPredict(m, grid, 'method', 'integral')));
      title('numerical approx of p(y=1|x)')
      
      % subfunction
      function plotPredictive(pred)
        contour(x1,x2,reshape(pred,[nx,nx]),30);
        hold on
        plot(X(find(y==1),1),X(find(y==1),2),'r.');
        plot(X(find(y==0),1),X(find(y==0),2),'bo');
      end
    end
    
    function demoOptimizer()
      logregDist.helperOptimizer('documents');
      logregDist.helperOptimizer('soy');
    end
    
    function helperOptimizer(dataset)
      setSeed(1);
      switch dataset
        case 'documents'
          load docdata; % n=900, d=600, C=2in training set
          y = ytrain-1; % convert to 0,1
          X = xtrain;
          methods = {'bb',  'cg', 'lbfgs', 'newton'};
        case 'soy'
          load soy; % n=307, d = 35, C = 3;
          y = Y; % turn into a binary classification problem by combining classes 1,2
          y(Y==1) = 0;
          y(Y==2) = 0;
          y(Y==3) = 1;
          methods = {'bb',  'cg', 'lbfgs', 'newton',  'boundoptRelaxed'};
      end
      lambda = 1e-3;
      figure; hold on;
      [styles, colors, symbols] =  plotColors;
      for mi=1:length(methods)
        tic
        [m, output{mi}] = fit(logregDist, 'X', X, 'y', y, 'lambda', lambda, 'method', methods{mi});
        T = toc
        time(mi) = T;
        w{mi} = m.w;
        niter = length(output{mi}.ftrace)
        h(mi) = plot(linspace(0, T, niter), output{mi}.ftrace, styles{mi});
        legendstr{mi}  = sprintf('%s', methods{mi});
      end
      legend(legendstr)
    end
    
  end
end