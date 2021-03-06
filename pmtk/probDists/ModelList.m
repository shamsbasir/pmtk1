classdef ModelList 
    % List of different models. We fit them all.
    % Subsequent calls to logprob/ predict/ impute use either best plugin model
    % or use Bayesian model averaging.
    
    properties
      models;
      bestNdx; % plugin
      bestModel;
      selMethod = 'bic';
      predMethod = 'plugin'; 
      nfolds = 5; costMean; costSe; % for CV
      loglik; penloglik; posterior; % for BIC etc
      occamWindowThreshold = 0;
      verbose = false;
      costFnForCV; % = (@(M,D) -logprob(M,D));
    end
    
    %%  Main methods
    methods
        function obj = ModelList(varargin)
          % ModelList(models, selMethod, nfolds, predMethod,
          % occamWindowThreshold, costFnForCV, verbose)
          % models is a cell array
          % selMethod - 'bic' or 'aic' or 'loglik' or 'cv' [default cv]
          % nfolds - number of folds [default 5]
          % predMethod - 'plugin' or 'bma'
          % occamWindowThreshold - for bma, use all models within this pc
          % of best model; 0 means use all models, 0.9 means use top 10%
          if nargin == 0; return; end
          [obj.models, obj.selMethod, obj.nfolds, ...
            obj.predMethod, obj.occamWindowThreshold, obj.costFnForCV, ...
            obj.verbose] = processArgs(varargin, ...
            '-models', {}, '-selMethod', 'bic', '-nfolds', 5, ...
            '-predMethod', 'plugin', '-occamWindowThreshold', 0, ...
            '-costFnForCV', (@(M,D) -logprob(M,D)), ...
            '-verbose', false);
        end
        
        function mlist = fit(mlist, D)
          % m = fit(m, D)
          % D is a DataTable
          % Stores best model in m.bestModel.
          % For BIC, updates m.models with fitted params.
          % Also stores vector of loglik/ penloglik (for BIC etc)
          % or LLmean/ LLse (for CV)
          Nx = ncases(D);
          assert(Nx>0)
          switch lower(mlist.selMethod)
            case 'cv', [mlist.models, mlist.bestNdx, mlist.costMean, mlist.costSe] = ...
                selectCV(mlist, D);
            otherwise
              % In statistics, one writes cost = deviance + cp*df
              % where deviance = -2*loglik, cp = complexity penalty, 
              % df = degrees of freedom.
              % We use score = loglik - cp*df
              % so our cp differs by a factor of 2.
              % (Why introduce the confusing term 'deviance'
              % when everything else is based on likelihood?)
              switch lower(mlist.selMethod)
                case 'bic', cp = log(Nx)/2;
                case 'aic',  cp =  1;
                case 'loglik', cp = 0; % for log marginal likelihood
              end
              [mlist.models, mlist.bestNdx, mlist.loglik, mlist.penloglik] = ...
                selectPenLoglik(mlist, D, cp);
              mlist.posterior = exp(normalizeLogspace(mlist.penloglik));
          end 
          mlist.bestModel = mlist.models{mlist.bestNdx};
        end
                    
        function ll = logprob(mlist, D)
          % ll(i) = logprob(m, D) 
          % D is a DataTable
          nX = ncases(D);
          switch mlist.predMethod
            case 'plugin'
              ll = logprob(mlist.models{mlist.bestNdx}, D);
            case 'bma'
              maxPost = max(mlist.posterior);
              f = mlist.occamWindowThreshold;
              ndx = find(mlist.posterior >= f*maxPost);
              nM = length(ndx);
              loglik  = zeros(nX, nM); %#ok
              logprior = log(mlist.posterior(ndx));
              logprior = repmat(logprior, nX, 1);
              for m=1:nM
                loglik(:,m) = logprob(mlist.models{ndx(m)}, D);
              end
              ll = logsumexp(loglik + logprior, 2);
          end % switch
        end % funciton
        
    end
    
    methods(Access = 'protected')
       function [models] = fitManyModels(ML, D)
        % May be overriden in subclass if efficient method exists
        % for computing full regularization path
        models = ML.models;
        Nm = length(models);
        for m=1:Nm
          models{m} = fit(models{m}, D);
        end
       end % fitManyModels
        
       function [models, bestNdx, loglik, penLL] = selectPenLoglik(ML, D, penalty)
        models = fitManyModels(ML, D);
        Nm = length(models);
        penLL = zeros(1, Nm);
        loglik = zeros(1, Nm);
        for m=1:Nm % for every model
          loglik(m) = sum(logprob(models{m}, D),1);
          if penalty==0
             penLL(m) = loglik(m); % for marginal likleihood, dof not defined
          else
            penLL(m) = loglik(m) - penalty*dof(models{m}); 
          end
        end
        bestNdx = argmax(penLL);
        %bestModel = models{bestNdx};
       end % selectPenLoglik
      
       function [models, bestNdx,  NLLmean, NLLse] = selectCV(ML, D)
         Nfolds = ML.nfolds;
         Nx = ncases(D);
         randomizeOrder = true;
         [trainfolds, testfolds] = Kfold(Nx, Nfolds, randomizeOrder);
         NLL = [];
         complexity = [];      
         for f=1:Nfolds % for every fold
           if ML.verbose, fprintf('starting fold %d of %d\n', f, Nfolds); end
           Dtrain = D(trainfolds{f});
           Dtest = D(testfolds{f});
           models = fitManyModels(ML, Dtrain);
           Nm = length(models);
           for m=1:Nm
             complexity(m) = dof(models{m}); %#ok
             nll = ML.costFnForCV(models{m}, Dtest); %logprob(models{m}, Dtest);
             NLL(testfolds{f},m) = nll; %#ok
           end
         end % f
         NLLmean = mean(NLL,1);
         NLLse = std(NLL,0,1)/sqrt(Nx);
         bestNdx = oneStdErrorRule(NLLmean, NLLse, complexity);
         %bestNdx = argmax(LLmean);
         % Now refit all models to all the data.
         % Typically we just refit the chosen model
         % but the extra cost of fitting all again is negligible since we've already fit
         % all models many times...
         ML.models = models;
         models = fitManyModels(ML, D);
         %bestModel = models{bestNdx};
       end


    end % methods 
    
    methods(Static = true)  
    end

end