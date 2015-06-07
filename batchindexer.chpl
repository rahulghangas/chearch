module BatchIndexer {

  use Logging, Random, SearchIndex, Time;
  
  config const batchDocumentCount = 1024 * 1024; // FAKE document count for testing
  config const maxTermsPerDocument = 10;
  config const maxTermsIds = 16384; // max number of terms across all docs

  class BatchIndexer {
    var release$: single bool;
    var t: Timer;

    proc startWorker() {
      begin {
        worker();
      }
    }

    proc waitForIndexer() {
      debug("waiting...");
      release$;
      debug("done waiting...");
    }

    proc worker() {
      local {
        var seed = (17 * here.id * 2) + 1;
        var randStreamSeeded: RandomStream = new RandomStream(seed);

        for externalDocId in 1..batchDocumentCount {
          var docSize = (randStreamSeeded.getNext() * maxTermsPerDocument): uint + 1;
          var terms: [0..docSize-1] IndexTerm;
          var textLocation: uint(8) = 0;
          for termId in terms.domain {
            terms[termId].term = (randStreamSeeded.getNext() * maxTermsIds): Term;
            terms[termId].textLocation = textLocation;
            textLocation += 1;
          }
          addDocument(terms, externalDocId: uint);
        }

        var localeKnownTermId = (here.id + 1024 * 1024) : Term;

        for externalDocId in batchDocumentCount+1..#1024 {
          var terms: [0..0] IndexTerm;
          var textLocation: uint(8) = 0;
          for termId in terms.domain {
            terms[termId].term = localeKnownTermId;
            terms[termId].textLocation = textLocation;
            textLocation += 1;
          }
          addDocument(terms, externalDocId: uint);
        }
      }

      release$ = true;
    }
  }

  const Space = {0..Locales.size-1};
  const ReplicatedSpace = Space dmapped ReplicatedDist();
  var batchIndexers: [ReplicatedSpace] BatchIndexer;

  proc startBatchIndexers() {
    var t: Timer;
    t.start();

    for loc in Locales {
      on loc {
        local {
          batchIndexers[here.id] = new BatchIndexer();
        }
        batchIndexers[here.id].startWorker();
      }
    }
    
    t.stop();
    timing("started batch indexers in ",t.elapsed(TimeUnits.microseconds), " microseconds");
  }

  proc waitForBatchIndexers() {
    var t: Timer;
    t.start();

    for loc in Locales {
      on loc {
        batchIndexers[here.id].waitForIndexer();
      }
    }
    
    t.stop();
    timing("stopped batch indexers in ",t.elapsed(TimeUnits.microseconds), " microseconds");
  }
}