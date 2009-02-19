classdef JtreeInfEng < InfEng
% Performs calibration using sum-product message passing on the clique tree
% induced by the client model. 
    
   properties
        factors;                % the original tabular factors - unaltered
        domain;                 % the entire domain of the client model
        nstates;                % nstates{i} = the number of states in variable domain(i)
        cliques;                % a cell array of TabularFactors, representing the cliques
        sepsets;                % sepsets{i,j} = cliques{i}.domain intersect cliques{j}.domain (symmetric)
        messages;               % a 2D cell array s.t. messages{i,j} = the message passed from clique i to clique j. Each message is a TabularFactor.
        cliqueLookup;           % cliqueLookup(i,j) = true iff variable i is in the scope of clique j
        factorLookup;           % factorLookup(f,c) = true iff eng.factors{f} was used in the construction of eng.cliques{c}
        cliqueTree;             % The clique tree as an adjacency matrix
        cliqueScope;            % a cell array s.t. cliqueScope{i} = the scope,(domain) of the ith clique.
        iscalibrated = false;   % true iff the clique tree is calibrated so that each clique represents the unnormalized joint over the variables in its scope. 
        orderDown;              % the order in which the cliques were visited in the downwards pass of calibration. 
   end
   
   
   methods
       
       function eng = JtreeInfEng()
           eng; %#ok
       end
       
       function eng = condition(eng,model,visVars,visVals)
           if eng.iscalibrated && (nargin < 3 || isempty(visVars))
               return; % nothing to do
           end
           
           if eng.iscalibrated && nargin == 4
               eng = recalibrate(eng,visVars,visValues); % recalibrate based on new evidence. 
               return;
           end
           
           if(nargin < 4), visVars = []; visVals = {}; end
           [eng.factors,eng.nstates] = convertToTabularFactors(model,visVars,visVals);
           eng.domain = model.domain;
           if isempty(eng.cliques)
               eng = setupCliqueTree(eng,model.G);  
           end
           eng = calibrate(eng);
       end
       
       function [postQuery,eng] = marginal(eng,queryVars)
           assert(eng.iscalibrated);
           cliqueNDX = findClique(eng,queryVars);
           if isempty(cliqueNDX)
               postQuery = outOfCliqueQuery(eng,queryVars);
           else
               postQuery = normalizeFactor(marginalize(eng.cliques{cliqueNDX},queryVars));
           end
       end
       
       function samples = sample(eng,n)
           samples = sample(normalizeFactor(TabularFactor.multiplyFactors(eng.factors)),n);
       end
       
       function logZ = lognormconst(eng)
            [Tfac,Z] = normalizeFactor(TabularFactor.multiplyFactors(eng.factors)); %#ok
            logZ = log(Z);
       end

   end
    
    
    methods(Access = 'protected')
        
        
        function eng = setupCliqueTree(eng,G)
        % create a clique tree from the initial graph G, add factors to the
        % cliques, and create the separating sets. 
        
            nfactors = numel(eng.factors);
            ncliques = [];
            buildCliqueTree();
            addFactorsToCliques();
            constructSeparatingSets();
             
            function buildCliqueTree()
                if G.directed, G = moralize(G);  end
                initialGraph = G.adjMat;            % graph of the client model
                for f=1:nfactors
                    dom = eng.factors{f}.domain;
                    initialGraph(dom,dom) = 1;      % connect up factors whose scope overlap to ensure they will live in the same cliques. 
                end
                initialGraph = setdiag(initialGraph,0);
                treeObj = Jtree(initialGraph);      % The jtree class triangulates and forms a cluster tree satisfying RIP
                eng.cliqueTree  = treeObj.adjMat;   % the adjacency matrix of the clique tree
                eng.cliqueScope = treeObj.cliques;  % the scope of each clique
                ncliques = numel(eng.cliqueScope);
                eng.cliqueLookup = false(numel(eng.domain),ncliques);
                for c=1:ncliques
                    eng.cliqueLookup(eng.cliqueScope{c},c) = true; % cliqueLookup(v,c) = true iff variable v is in the scope of clique c
                end
            end
            
            function addFactorsToCliques()
            % add each factor to the smallest accommodating clique   
                eng.factorLookup = false(nfactors,ncliques);
                for f=1:nfactors
                    candidateCliques = all(eng.cliqueLookup(eng.factors{f}.domain,:),1);
                    c = minidx(cellfun(@(x)numel(x),eng.cliqueScope(candidateCliques))); 
                    eng.factorLookup(f,sub(find(candidateCliques),c)) = true;
                end
                eng.cliques = cell(ncliques,1);
                for c=1:ncliques
                    scope = eng.cliqueScope{c};
                    T = ones(eng.nstates(scope));
                    eng.cliques{c} = TabularFactor.multiplyFactors({TabularFactor(T,scope),eng.factors{eng.factorLookup(:,c)}});
                end
            end
            
            function constructSeparatingSets()
            % for each edge in the clique tree, construct the separating set.     
                eng.sepsets = cell(ncliques);
                [is,js] = find(eng.cliqueTree);
                for k=1:numel(is)
                    i = is(k); j = js(k);
                    eng.sepsets{i,j} = myintersect(eng.cliques{i}.domain,eng.cliques{j}.domain);
                    eng.sepsets{j,i} = eng.sepsets{i,j};
                end
            end
            
        end % end of setupCliqueTree method
        
        function eng = recalibrate(eng,visVars, visVals)
         % recalibrate based on new evidence.    
           error('recalibration of an already calibrated tree based on new evidence is not yet implemented'); 
        end
        
        
        function postQuery = outOfCliqueQuery(eng,queryVars)
        % perform variable elimination to answer the out of clique query    
            
            ntotalCliques = numel(eng.cliques);
            includeCliques = false(1,ntotalCliques);
            varsRemaining = queryVars;
            while not(isempty(varsRemaining))  
                bestClique = maxidx(sum(eng.cliqueLookup(varsRemaining,:),1)); % clique that contains the most number of vars in varsRemaining.
                includeCliques(bestClique) = true;
                varsRemaining = mysetdiff(varsRemaining,eng.cliques{bestClique}.domain);
            end
            subtree = minSubTree(eng.cliqueTree,sub(1:ntotalCliques,includeCliques));
            cliqueNDX = find(sum(subtree,1) | sum(subtree,2)');
            [junk,cliqueNDX] = ismember(cliqueNDX,eng.orderDown);
            cliqueNDX = cliqueNDX(end:-1:1);
           
            nfactors = numel(cliqueNDX);
            factors = cell(1,nfactors);
           
            for f=1:nfactors-1
               c = cliqueNDX(f);
               mu = marginalize(eng.cliques{c},eng.sepsets{c,cliqueNDX(f+1)});
               factors{f} = divideBy(eng.cliques{c},mu);
            end
            factors(nfactors) = eng.cliques(cliqueNDX(end));
            elim = mysetdiff(unique(cell2mat(cellfuncell(@(fac)rowvec(fac.domain),factors))),queryVars);
            postQuery = normalizeFactor(variableElimination(factors,elim));
        end
        
        function ndx = findClique(eng,queryVars)
        % find a clique to answer the answer the query, if any.
            dom = 1:size(eng.cliqueLookup,1);
            candidates = dom(all(eng.cliqueLookup(queryVars,:),1));
            if isempty(candidates)
                ndx = []; 
            elseif numel(candidates) == 1
               ndx = candidates;
            else % return the smallest valid clique;
               ndx = candidates(minidx(cellfun(@(x)numel(x),eng.cliques(candidates))));
            end
        end
        
        function eng = calibrate(eng)
        % perform an upwards and downwards pass so that each clique represents 
        % the unnormalized distribution over the variables in its scope.
            
            jtree = triu(eng.cliqueTree); 
            % We treat the clique tree as directed here to implicitly define a
            % topological ordering of the nodes - traversal will queue based,
            % (i.e. breadth first search), starting with the leaves. The 'queue'
            % is the readyToSend logical vector defined below. 
           
            ncliques = numel(eng.cliques);
            eng.messages = cell(ncliques);            % we store all of the messages to allow for faster recalibration given new evidence. 
            rm = @(c)c(cellfun(@(x)~isempty(x),c));   % simple function to remove empty entries in a cell array
            allexcept = @(x)[1:x-1,(x+1):ncliques];   % returns the same answer as setdiff(1:ncliques,x)
            root = sub(1:ncliques,not(sum(jtree,1))); % nodes with no parents (inwards links in the directed clique tree)
            assert(numel(root) == 1);                 % otherwise its not a directed tree!
            readyToSend = false(1,ncliques);          % readyToSend(c) = true iff clique c is ready to send its message to its parent in the upwards pass or its children in the downwards pass
            readyToSend(not(sum(jtree,2))) = true;    % leaves are ready to send up
            
            % upwards pass
            while not(readyToSend(root))    
                current = sub(sub(1:ncliques,readyToSend),1); % this is the first ready clique in the queue
                parent = parents(jtree,current); assert(numel(parent) == 1);     
                psi = TabularFactor.multiplyFactors(rm({eng.cliques{current},eng.messages{allexcept(parent),current}}));
                eng.messages{current,parent} = marginalize(psi,eng.sepsets{current,parent});
                readyToSend(current) = false; % already sent
                % parent ready to send if there are messages from all of its children
                readyToSend(parent)  = all(cellfun(@(x)~isempty(x),eng.messages(children(jtree,parent),parent))); 
            end
            assert(sum(readyToSend) == 1) % only root left to send
            eng.orderDown = zeros(1,ncliques);
            counter = 1;
            % downwards pass
            while(any(readyToSend))
                current = sub(sub(1:ncliques,readyToSend),1);
                eng.orderDown(counter) = current;
                counter = counter + 1;
                C = children(jtree,current);
                for i=1:numel(C)
                    child = C(i);
                    psi = TabularFactor.multiplyFactors(rm({eng.cliques{current},eng.messages{allexcept(child),current}})); 
                    eng.messages{current,child} = marginalize(psi,eng.sepsets{current,child});
                    readyToSend(child) = true;
                end
                readyToSend(current) = false;
            end
            
            % update the cliques with all of the messages sent to them
            for c=1:ncliques
               eng.cliques{c} = TabularFactor.multiplyFactors(rm({eng.cliques{c},eng.messages{:,c}})); 
            end
            eng.iscalibrated = true;
        end % end of calibrate method
    end % end of protected methods block
end % end of class