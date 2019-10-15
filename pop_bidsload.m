% pop_bidsload - This function allows for the ingesting of a single BIDS
%               file. In the case of EDFs, the directory of the data file
%               is searched for an event tsv and an electrodes tsv. These
%               are then read back into the EEG structure.
%
% Usage:
%    bids_export(fileLocation, varargin)
%
% Input:
%  fileLocation - [String] location of a file. In the case of EDFs, the
%                 directory the file is located in will be searched for an
%                 events/electrodes file.
%
% Optional inputs:
%  'elecLoc'    - [String] explicit location of the electrodes tsv.
%
%  'eventLoc'   - [String] explicit location of the events tsv.
%
%  'gui'        - [logical] toggle for redrawing main eeglab figure. 
%                 Defaults to true.
%
%  'icaSphere'  - [String] location of an ICA sphering matrix. If empty,
%                 nothing will be loaded. Both ICA options must be present
%                 to complete loading.
%
%  'icaWeights' - [String] location of ICA vector matrix. If empty, nothing
%                 will be loaded. Both ICA options must be present to
%                 complete loading. This option will also be used to read a
%                 json which contains the channels that the ICA was run on.
%
%  'annoLoc'    - [String] location of discrete annotation BIDS tsv. The
%                 paired files will be assumed to be in the same location.
%                 By using this option, EEG.marks will be cleared first.
%                 See other options for continuous marks integration.
%
% Author: Tyler K. Collins, 2019

function EEG = pop_bidsload(fileLocation, varargin)

    if nargin < 1
        help pop_bidsload;
        return;
    end

    % Future proofing against wanting to point a datafile to different
    % locations due to inheritence principle.
    opt = finputcheck(varargin, {'elecLoc' 'string' {} '';
                                 'gui' 'integer' {} 1;
                                 'icaSphere' 'string' {} '';
                                 'icaWeights' 'string' {} '';
                                 'annoLoc' 'string' {} '';
                                 'eventLoc' 'string' {} ''}, 'bids_format_eeglab');

    [fPath,fName,fType] = fileparts(fileLocation);
    fullFile = [fPath '/' fName fType];

    if strcmp(fType,'.set') % Easy case
        disp('Set file detected. Loading as normal.');
        EEG = pop_loadset(fullFile,'');
    elseif strcmp(fType,'.edf') % Requires processing
        disp('BIDS Parsing needed.');
        EEG = pop_biosig(fullFile);

        % Relabel events
        eventData = validateBidsFile(fullFile, opt.eventLoc, 'events');
        for i=1:length(eventData.value)
            try % Octave case
                EEG.event(i).type = strtrim(eventData.value{i,:});
            catch % Matlab case
                EEG.event(i).type = strtrim(eventData.value(i,:));
            end
        end

        % Update channel/electrode locations
        % Accounts for chanlocs and the tsv being out of order
        % Also strips extra whitespace from tsv reading
        % parsedElec structure also keeps track of if it has been used
        elecData = validateBidsFile(fullFile, opt.elecLoc, 'electrodes');
        parsedElec = cell(length(elecData.name),2);
        for i=1:length(parsedElec)
            parsedElec{i,1} = strtrim(elecData.name(i,:));
            parsedElec{i,2} = false;
        end
        
        % Look up loop
        for i=1:length(EEG.chanlocs)
            lookupID = -1;
            for j=1:length(parsedElec)
                if strcmp(EEG.chanlocs(i).labels, parsedElec{j,1})
                    lookupID = j;
                    parsedElec{j,2} = true;
                    break;
                end
            end
            
            if lookupID < 0
                warning([currentLabel ' not found. Adding to nodatchans']);
            else
                % Loss of precision is only a printing error
                % Use "format long" to double check
                EEG.chanlocs(i).X = elecData.x(lookupID);
                EEG.chanlocs(i).Y = elecData.y(lookupID);
                EEG.chanlocs(i).Z = elecData.z(lookupID);
            end
        end
        
        % Any labels that were not used are moved into the fiducial struct
        for i=1:length(parsedElec)
            if ~parsedElec{i,2}
                disp(['Moving ' parsedElec{i,1}  ' to nodatchans']);
                if isempty(EEG.chaninfo.nodatchans) % Initial copy edge case
                    EEG.chaninfo.nodatchans = EEG.chanlocs(1);
                    EEG.chaninfo.nodatchans(1).type = 'FID';
                    EEG.chaninfo.nodatchans(1).datachan = 0;
                else % Just copy from the previous
                    EEG.chaninfo.nodatchans(end+1) = EEG.chaninfo.nodatchans(1);
                end
                % Read info
                EEG.chaninfo.nodatchans(end).labels = parsedElec{i,1};
                EEG.chaninfo.nodatchans(end).X = elecData.x(i);
                EEG.chaninfo.nodatchans(end).Y = elecData.y(i);
                EEG.chaninfo.nodatchans(end).Z = elecData.z(i);
            end
        end
        
        % Take advantage of eeglab function
        EEG = eeg_checkset(EEG,'chanconsist');
    end
    
    % ICA Loading
    if ~strcmp(opt.icaSphere,'') && ~strcmp(opt.icaSphere,'')
        disp('Attempting to load ICA decomposition via: ');
        disp(opt.icaSphere);
        disp(opt.icaWeights);
        weightsJson = loadjson(strrep(opt.icaWeights,'.tsv','.json'));
        EEG.icachansind = weightsJson.icachansind;
        EEG.icaweights = dlmread(opt.icaWeights,'\t');
        EEG.icasphere = dlmread(opt.icaSphere,'\t');
        EEG = eeg_checkset(EEG); % Force rebuild now that ICA is back
    elseif ~strcmp(opt.icaSphere,'') || ~strcmp(opt.icaSphere,'')
        disp('Only one ICA option given. Both are required.');
    end
    
    % Mark structure ingest
    if ~strcmp(opt.annoLoc,'')
        if ~exist('ve_eegplot')
            error('VisedMarks not found. Unable to ingest annotations');
        end
        annoJsonLoc = strrep(opt.annoLoc,'.tsv','.json');
        if ~exist(annoJsonLoc)
            error('BIDS Annotation JSON not found.');
        end
        disp('Rebuiling marks structure via:');
        disp(opt.annoLoc);
        disp(annoJsonLoc);
        
        EEG.marks = [];
        if isempty(EEG.icaweights)
            EEG.marks=marks_init(size(EEG.data));
        else
            EEG.marks=marks_init(size(EEG.data),min(size(EEG.icaweights)));
        end
        
        annoData = tdfread(opt.annoLoc);
        for i=1:length(annoData.onset) % all the same size in rows
            onsetTime = str2num(strtrim(annoData.onset(i,:)));
            durationTime = str2num(strtrim(annoData.duration(i,:)));
            currentLabel = strtrim(annoData.label(i,:));
            % Chan or comp marker
            if isempty(onsetTime) && isempty(durationTime)
                if strncmpi(currentLabel,'chan',4)
                    EEG = ingestMark(EEG, 0, currentLabel,'chan_', 'EEG',strtrim(annoData.channels(i,:)));
                elseif strncmpi(currentLabel,'comp',4)
                    EEG = ingestMark(EEG, 1, currentLabel,'comp_','ICA',strtrim(annoData.channels(i,:)));
                else
                    warning('Mark ingest not defined for mark of this type.');
                end
            else % Time info mark case
                [EEG, markID] = timeMarkExist(EEG, currentLabel);
                startPos = round(onsetTime * EEG.srate);
                endPos = round(durationTime * EEG.srate) + startPos;
                for index=startPos:endPos
                    EEG.marks.time_info(markID).flags(index) = 1;
                end
            end
        end
        
        % Test if continuous annotations need to be handled
%         contMarkTsv = strrep(opt.annoLoc,'_annotations.tsv','timeinfo_annotations.tsv');
%         contMarkJson = strrep(contMarkTsv,'.tsv','.json');
%         if exist(contMarkTsv) && exist(contMarkJson)
%             disp('Continuous marks files found at:');
%             disp(contMarkTsv);
%             disp(contMarkJson);
%             
%             % Get headers from json
%             contMarkInfo = loadjson(contMarkJson);
%             contData = dlmread(contMarkTsv, '\t');
%             % For each header in the colums, make a new mark and read from
%             % the data tsv
%             for i=1:length(contMarkInfo.Columns)
%                 [EEG, markID] = timeMarkExist(EEG,contMarkInfo.Columns{i});
%                 EEG.marks.time_info(markID).flags = contData(:,i)';
%             end
%             disp('Continuous marks loaded.');
%         end
        contMarkMat = strrep(opt.annoLoc,'.tsv','.mat');
        if exist(contMarkMat)
            disp('Continuous mark file found. Loading at: ');
            disp(contMarkMat);
            contData = load(contMarkMat);
            for i=1:length(contData.timeAccum)
                EEG.marks.time_info(end+1) = contData.timeAccum{i};
            end
        end
    end
    
    % Draw to main figure
    if opt.gui
        eval('eeglab redraw'); % Double draw for edge case.
        % eval('eeglab redraw');
    end
end