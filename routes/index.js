var players = require('../lib/players');

/*
 * GET home page.
 */
module.exports = function(req, res)
{
  players.getAll
  (
    function(playerList)
    {
      res.render('index', {pretty: true, players: playerList});
    }
  );
};
