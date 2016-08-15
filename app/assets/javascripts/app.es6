import {run} from '@cycle/xstream-run';
import {makeDOMDriver, div, h1, h2, pre} from '@cycle/dom';
import {makeHTTPDriver} from '@cycle/http';
import xs from 'xstream';
import _ from 'lodash';

function debug (v) {
  return pre(JSON.stringify(v, null, 2));
}

function renderBlock () {
  return (
    div('.block')
  );
}

function renderActivity (activity) {
  return (
    div('.activity', [
      h2('.name', activity.name),
      div('.blocks', _.range(activity.time_blocks_per_week).map(renderBlock))
    ])
  );
}

function view (activities) {
  return (
    div('.view', [
      h1('Activities'),
      div('.activities', activities.map(renderActivity)),

      div('.queue')
    ])
  );
}

function main ({DOM, HTTP}) {
  const activities$ = HTTP
    .select('activities')
    .flatten()
    .map(response => response.body)
    .startWith([]);

  const requestActivities$ = xs
    .of({
      url: '/activities',
      category: 'activities'
    });

  return {
    DOM: activities$.map(view),
    HTTP: requestActivities$
  };
}

const drivers = {
  DOM: makeDOMDriver('.app'),
  HTTP: makeHTTPDriver()
};

export default function () {
  run(main, drivers);
}
