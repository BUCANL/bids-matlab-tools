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
%  'elecLoc'  - [String] explicit location of the electrodes tsv.
%
%  'eventLoc' - [String] explicit location of the events tsv.
%
%  'gui'      - [logical] toggle for redrawing main eeglab figure. Defaults
%               to true.
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
                    EEG.chaninfo.nodatchans(i) = EEG.chaninfo.nodatchans(1);
                end
                % Read info
                EEG.chaninfo.nodatchans(i).labels = parsedElec{i,1};
                EEG.chaninfo.nodatchans(i).X = elecData.x(i);
                EEG.chaninfo.nodatchans(i).Y = elecData.y(i);
                EEG.chaninfo.nodatchans(i).Z = elecData.z(i);
            end
        end
        
        % Take advantage of eeglab function
        EEG = eeg_checkset(EEG,'chanconsist');
    end
    % Draw to main figure
    if opt.gui
        eval('eeglab redraw;'); % Double draw for edge case.
        eval('eeglab redraw;');
    end
end

% Helper function for grabbing data out of a BIDS tsv given a location
function dataStruct = validateBidsFile(file, fileStruct, fileSuffix)
    if strcmp(fileStruct,'')
        fileStruct = strrep(file,'_eeg.edf',['_' fileSuffix '.tsv']);
        disp(['Assuming local BIDS ' fileSuffix ' file at: ' fileStruct]);
    else
        disp(['Using explicit BIDS ' fileSuffix ' file at: ' fileStruct]);
    end
    
    try
        dataStruct = tdfread(fileStruct); % Matlab case
    catch ME
        disp('Running in Octave mode...');
        holdMe = csv2cell(fileStruct,'	'); % Octave case
        if strcmp(fileSuffix,'events')
            colID = find(strcmp('value',holdMe(1,:))); % Search for value column
            dataStruct.value = holdMe(2:end,colID);
        elseif strcmp(fileSuffix,'electrodes')
            xID = find(strcmp('x',holdMe(1,:)));
            yID = find(strcmp('y',holdMe(1,:)));
            zID = find(strcmp('z',holdMe(1,:)));
            nameID = find(strcmp('name',holdMe(1,:)));
            dataStruct.x = [holdMe{2:end,xID}];
            dataStruct.y = [holdMe{2:end,yID}];
            dataStruct.z = [holdMe{2:end,zID}];
            dataStruct.name = holdMe(2:end,nameID);
        end
    end
end
    